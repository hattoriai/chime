defmodule Chime.Notify do
  @moduledoc false
  # Chime.notify/3: the event, then each person's notification, grouped or
  # new, their deliveries and jobs, and their counts, a batch at a time.
  #
  # The event and the first batch are one transaction, so that a call with
  # an idempotency key that was made already does nothing at all. A batch
  # is 1000 people; each after the first is a transaction of its own, so
  # that one event to many people does not hold a transaction for long.

  import Ecto.Query

  alias Chime.{Config, Counts, Delivery, Event, Fanout, Notification, Preferences, Resolver}

  @batch 1000
  @max_actors 20

  @doc false
  @spec run(Config.t(), module(), term(), keyword()) ::
          {:ok, Event.t()} | {:error, :duplicate, Event.t()}
  def run(%Config{} = config, notifier, params, opts) do
    unless Chime.Notifier.notifier?(notifier) do
      raise ArgumentError, "#{inspect(notifier)} is not a Chime.Notifier"
    end

    now = opts |> Keyword.get_lazy(:now, &DateTime.utc_now/0) |> Chime.Schema.usec()
    category = Config.category(config, notifier.__chime__(:category))
    deliveries = notifier.__chime__(:deliveries)
    Enum.each(deliveries, &check_channel(config, notifier, &1.channel))

    ids = recipient_ids(config, notifier, params, opts)
    kind = notifier.__chime__(:kind)

    # A group is a notifier's own: two notifiers with the same key do not
    # join each other's notifications.
    group = notifier.group(params)
    group = group && "#{kind}:#{group}"

    event = %{
      id: Ecto.UUID.generate(),
      notifier: inspect(notifier),
      kind: kind,
      category: category.key,
      data: notifier.data(params),
      actor: notifier.actor(params),
      group_key: group,
      key: opts[:key],
      recipients: length(ids),
      inserted_at: now
    }

    plan = %{
      config: config,
      notifier: notifier,
      event: event,
      category: category,
      required: notifier.__chime__(:required) or category.required,
      feed: Enum.any?(deliveries, &(&1.channel == "feed")),
      channels: Enum.reject(deliveries, &(&1.channel == "feed")),
      now: now
    }

    [first | rest] = if ids == [], do: [[]], else: Enum.chunk_every(ids, @batch)

    first_batch =
      config.repo.transaction(fn ->
        case config.repo.insert_all(Event, [event],
               on_conflict: :nothing,
               conflict_target: :key,
               prefix: config.prefix
             ) do
          {1, _} ->
            close_groups(plan)
            batch(plan, first)

          {0, _} ->
            config.repo.rollback(:duplicate)
        end
      end)

    case first_batch do
      {:ok, counts} ->
        Fanout.notified(config, counts)
        Enum.each(rest, &rest_batch(plan, &1))

        :telemetry.execute([:chime, :notify], %{recipients: length(ids)}, %{
          notifier: notifier,
          event_id: event.id
        })

        {:ok, config.repo.get!(Event, event.id, prefix: config.prefix)}

      {:error, :duplicate} ->
        {:error, :duplicate, config.repo.get_by!(Event, [key: opts[:key]], prefix: config.prefix)}
    end
  end

  defp rest_batch(%{config: config} = plan, ids) do
    {:ok, counts} = config.repo.transaction(fn -> batch(plan, ids) end)
    Fanout.notified(config, counts)
  end

  defp check_channel(_config, _notifier, "feed"), do: :ok

  defp check_channel(%Config{mailer: nil}, notifier, "email") do
    raise ArgumentError,
          "#{inspect(notifier)} delivers by email, and Chime's config has no :mailer"
  end

  defp check_channel(config, _notifier, channel) do
    Config.channel(config, channel)
    :ok
  end

  # The ids of the people, once each: from :to, or the notifier.
  defp recipient_ids(config, notifier, params, opts) do
    recipients =
      case Keyword.fetch(opts, :to) do
        {:ok, to} ->
          List.wrap(to)

        :error ->
          unless function_exported?(notifier, :recipients, 1) do
            raise ArgumentError,
                  "#{inspect(notifier)} has no recipients/1: write it, or give Chime.notify/3 :to"
          end

          notifier.recipients(params)
      end

    recipients
    |> Enum.map(&(config.resolver |> Resolver.to_recipient(&1) |> Resolver.id()))
    |> Enum.uniq()
  end

  # The groups whose window has passed take no more events: once for the
  # event, for every person.
  defp close_groups(%{event: %{group_key: nil}}), do: :ok

  defp close_groups(%{config: config, event: event, now: now}) do
    from(n in Notification,
      where: n.group_key == ^event.group_key and n.grouping and n.grouped_until <= ^now
    )
    |> config.repo.update_all([set: [grouping: false]], prefix: config.prefix)

    :ok
  end

  # One batch of people: their settings, their notifications (new, or the
  # open group's), the deliveries and their jobs, and their counts.
  defp batch(_plan, []), do: %{}

  defp batch(%{config: config} = plan, ids) do
    # The people's counts locked first, so that what follows sees what
    # other calls for the same people committed, and they wait for this.
    Counts.lock(config, ids)
    kept = Preferences.stored(config, ids, plan.category.key)

    in_feed =
      Map.new(ids, fn id ->
        {setting, _at} =
          Preferences.setting(plan.category, plan.required, Map.get(kept, id, %{}), "feed")

        {id, plan.feed and setting == "on"}
      end)

    {new, joined} = notifications(plan, ids, in_feed)
    deliveries(plan, new, joined, kept)

    Counts.refresh(config, ids)
  end

  # The notifications of a batch: those of an open group take the event,
  # the others are new. {new, joined}, each [{recipient, notification_id}].
  defp notifications(%{event: %{group_key: nil}} = plan, ids, in_feed) do
    {insert(plan, ids, in_feed), []}
  end

  defp notifications(%{config: config, event: event} = plan, ids, in_feed) do
    open =
      from(n in Notification,
        where: n.recipient in ^ids and n.group_key == ^event.group_key and n.grouping,
        select: {n.recipient, n.id, n.actors}
      )
      |> config.repo.all(prefix: config.prefix)

    joined = join_groups(plan, open, in_feed)
    joined_ids = MapSet.new(joined, &elem(&1, 0))
    {insert(plan, Enum.reject(ids, &MapSet.member?(joined_ids, &1)), in_feed), joined}
  end

  # The event joins the open groups: one update for each list of actors,
  # which the notifications of a group most often share.
  defp join_groups(_plan, [], _in_feed), do: []

  # A notification read or archived meanwhile is not joined (its update
  # checks it is still open): the person gets a new one.
  defp join_groups(%{config: config, event: event, now: now}, open, in_feed) do
    open
    |> Enum.group_by(fn {recipient, _id, actors} -> {actors, in_feed[recipient]} end)
    |> Enum.flat_map(fn {{actors, feed?}, rows} ->
      ids = Enum.map(rows, &elem(&1, 1))
      new_actor = if new_actor?(actors, event.actor), do: 1, else: 0

      {_n, joined} =
        from(n in Notification, where: n.id in ^ids and n.grouping, select: {n.recipient, n.id})
        |> config.repo.update_all(
          [
            set: [
              event_id: event.id,
              actors: add_actor(actors, event.actor),
              in_feed: feed?,
              seen_at: nil,
              updated_at: now
            ],
            inc: [count: 1, actor_count: new_actor]
          ],
          prefix: config.prefix
        )

      joined
    end)
  end

  defp new_actor?(_actors, nil), do: false

  defp new_actor?(actors, actor) do
    id = actor["id"] || actor[:id]
    not Enum.any?(actors, &((&1["id"] || &1[:id]) == id))
  end

  defp add_actor(actors, nil), do: actors

  defp add_actor(actors, actor) do
    id = actor["id"] || actor[:id]
    [actor | Enum.reject(actors, &((&1["id"] || &1[:id]) == id))] |> Enum.take(@max_actors)
  end

  defp insert(_plan, [], _in_feed), do: []

  defp insert(%{config: config, event: event, now: now} = plan, ids, in_feed) do
    grouping = event.group_key != nil
    until = if grouping, do: DateTime.add(now, plan.notifier.__chime__(:group_window))

    rows =
      Enum.map(ids, fn id ->
        %{
          id: Ecto.UUID.generate(),
          recipient: id,
          event_id: event.id,
          kind: event.kind,
          category: event.category,
          group_key: event.group_key,
          grouping: grouping,
          grouped_until: until,
          count: 1,
          actors: if(event.actor, do: [event.actor], else: []),
          actor_count: if(event.actor, do: 1, else: 0),
          in_feed: in_feed[id],
          inserted_at: now,
          updated_at: now
        }
      end)

    if grouping do
      # The counts' lock keeps two calls for the same people apart, so an
      # open group of theirs made meanwhile was seen: this is a safeguard.
      {_n, inserted} =
        config.repo.insert_all(Notification, rows,
          on_conflict: :nothing,
          conflict_target: {:unsafe_fragment, "(recipient, group_key) WHERE grouping"},
          returning: [:id, :recipient],
          prefix: config.prefix
        )

      Enum.map(inserted, &{&1.recipient, &1.id})
    else
      config.repo.insert_all(Notification, rows, prefix: config.prefix)
      Enum.map(rows, &{&1.recipient, &1.id})
    end
  end

  # The deliveries of the channels but the feed. A new notification has
  # one for each channel: waiting for its time, or skipped when the person
  # turned the channel off. A group's has one more only when none waits:
  # the one that waits goes with the group as it is then.
  defp deliveries(%{channels: []}, _new, _joined, _kept), do: :ok

  defp deliveries(%{config: config, channels: channels, now: now} = plan, new, joined, kept) do
    rows =
      for {notifications, new?} <- [{new, true}, {joined, false}],
          {recipient, notification_id} <- notifications,
          channel <- channels,
          row = delivery(plan, recipient, notification_id, channel, kept, new?, now),
          row != nil,
          do: row

    {scheduled, skipped} = Enum.split_with(rows, &(&1.status == "scheduled"))

    skipped
    |> Enum.chunk_every(@batch)
    |> Enum.each(&config.repo.insert_all(Delivery, &1, prefix: config.prefix))

    scheduled
    |> Enum.chunk_every(@batch)
    |> Enum.each(fn rows ->
      {_n, inserted} =
        config.repo.insert_all(Delivery, rows,
          on_conflict: :nothing,
          conflict_target:
            {:unsafe_fragment, "(notification_id, channel) WHERE status = 'scheduled'"},
          returning: [:id, :scheduled_at],
          prefix: config.prefix
        )

      Chime.Jobs.deliveries(config, inserted)
    end)
  end

  defp delivery(plan, recipient, notification_id, channel, kept, new?, now) do
    {setting, at} =
      Preferences.setting(
        plan.category,
        plan.required,
        Map.get(kept, recipient, %{}),
        channel.channel
      )

    row = %{
      id: Ecto.UUID.generate(),
      notification_id: notification_id,
      recipient: recipient,
      channel: channel.channel,
      attempts: 0,
      inserted_at: now,
      updated_at: now
    }

    cond do
      setting == "off" and new? ->
        Map.merge(row, %{
          status: "skipped",
          reason: Chime.Explain.turned_off(plan.category, channel.channel, at),
          scheduled_at: now
        })

      setting == "off" ->
        nil

      true ->
        Map.merge(row, %{status: "scheduled", scheduled_at: DateTime.add(now, channel.wait)})
    end
  end
end
