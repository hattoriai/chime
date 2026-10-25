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

    actor = notifier.actor(params)
    audience? = audience?(notifier, opts)

    {ids, known} =
      if audience?, do: {[], %{}}, else: recipients(config, notifier, params, opts, actor)

    kind = notifier.__chime__(:kind)

    workspace = workspace(notifier, params, opts)
    group = group_key(notifier, params, kind, workspace)

    event = %{
      id: Ecto.UUID.generate(),
      notifier: inspect(notifier),
      kind: kind,
      category: category.key,
      workspace: workspace,
      data: notifier.data(params),
      actor: actor,
      group_key: group,
      key: opts[:key],
      recipients: length(ids),
      inserted_at: now
    }

    plan = plan(config, notifier, event, deliveries, now, params: params, known: known)

    case {audience?, opts[:at]} do
      {true, at} -> start_audience(plan, at && Chime.Schema.usec(at), opts)
      {false, nil} -> now(plan, ids, opts)
      {false, at} -> schedule(plan, ids, Chime.Schema.usec(at), opts)
    end
  end

  # The notifier's audience/1 when it has no recipients/1, and :to does
  # not give the people.
  defp audience?(notifier, opts) do
    not Keyword.has_key?(opts, :to) and not function_exported?(notifier, :recipients, 1) and
      function_exported?(notifier, :audience, 1)
  end

  # An audience: the event "sending", and the job of its first page, now
  # or at its time (then "scheduled", as any).
  defp start_audience(%{config: config, event: event}, at, opts) do
    event =
      Map.merge(event, %{
        status: if(at, do: "scheduled", else: "sending"),
        scheduled_at: at,
        recipients: 0
      })

    result =
      config.repo.transaction(fn ->
        case insert_event(config, event) do
          :ok when at != nil -> Chime.Jobs.notify(config, event.id, at)
          :ok -> Chime.Jobs.audience(config, event.id, nil)
          :duplicate -> config.repo.rollback(:duplicate)
        end
      end)

    case result do
      {:ok, :ok} -> {:ok, config.repo.get!(Event, event.id, prefix: config.prefix)}
      {:error, :duplicate} -> duplicate(config, opts)
    end
  end

  @doc false
  # A page of an audience: the next 1000 people after the cursor, in the
  # page's transaction with the event's new cursor and the next page's
  # job, so that a page is done once. The job of a page done already, or
  # of an event cancelled, does nothing.
  @spec page(Config.t(), Ecto.UUID.t(), String.t() | nil, DateTime.t()) :: :ok
  def page(%Config{} = config, id, cursor, now \\ DateTime.utc_now()) do
    now = Chime.Schema.usec(now)

    result =
      config.repo.transaction(fn ->
        with %Event{status: "sending", cursor: ^cursor} = event <-
               config.repo.get(Event, id, prefix: config.prefix),
             notifier when notifier != nil <- Event.notifier(event) do
          do_page(config, notifier, event, now)
        else
          _ -> %{}
        end
      end)

    case result do
      {:ok, counts} -> Fanout.notified(config, counts)
    end

    :ok
  end

  @page 1000

  defp do_page(config, notifier, event, now) do
    key = notifier.__chime__(:audience_key)
    keys = audience_page(config, notifier, event, key)

    actor = event.actor && (event.actor["id"] || event.actor[:id])

    ids =
      keys
      |> Enum.map(&notifier.recipient_id/1)
      |> Enum.reject(&(&1 == actor and not notifier.__chime__(:notify_actor)))

    plan =
      plan(
        config,
        notifier,
        Map.take(event, [:id, :kind, :category, :workspace, :data, :actor, :group_key]),
        notifier.__chime__(:deliveries),
        now,
        []
      )

    if event.cursor == nil, do: close_groups(plan)
    counts = batch(plan, ids)

    last = List.last(keys)
    done? = length(keys) < @page
    cursor = if last == nil, do: event.cursor, else: JSON.encode!(last)

    from(e in Event, where: e.id == ^event.id)
    |> config.repo.update_all(
      [
        set: [cursor: cursor, status: if(done?, do: "sent", else: "sending")],
        inc: [recipients: map_size(counts)]
      ],
      prefix: config.prefix
    )

    unless done?, do: Chime.Jobs.audience(config, event.id, cursor)
    counts
  end

  defp audience_page(config, notifier, event, key) do
    query =
      event.data
      |> notifier.audience()
      |> Ecto.Queryable.to_query()
      |> exclude(:order_by)
      |> exclude(:select)
      |> exclude(:limit)
      |> exclude(:preload)
      |> order_by([x], asc: field(x, ^key))
      |> select([x], field(x, ^key))
      |> limit(@page)

    query =
      case event.cursor do
        nil -> query
        cursor -> where(query, [x], field(x, ^key) > ^JSON.decode!(cursor))
      end

    config.repo.all(query)
  end

  defp plan(config, notifier, event, deliveries, now, opts) do
    feed = Enum.find(deliveries, &(&1.channel == "feed"))
    category = Config.category(config, event.category)

    %{
      config: config,
      notifier: notifier,
      params: opts[:params],
      known: Keyword.get(opts, :known, %{}),
      guard: Keyword.has_key?(opts, :params) and function_exported?(notifier, :notify?, 2),
      feed_spec: feed,
      event: event,
      category: category,
      required: notifier.__chime__(:required) or category.required,
      feed: feed != nil,
      channels: Enum.reject(deliveries, &(&1.channel == "feed")),
      now: now
    }
  end

  defp now(%{config: config, event: event} = plan, ids, opts) do
    [first | rest] = batches(ids)

    first_batch =
      config.repo.transaction(fn ->
        case insert_event(config, event) do
          :ok ->
            close_groups(plan)
            batch(plan, first)

          :duplicate ->
            config.repo.rollback(:duplicate)
        end
      end)

    case first_batch do
      {:ok, counts} -> {:ok, finish(plan, ids, counts, rest)}
      {:error, :duplicate} -> duplicate(config, opts)
    end
  end

  defp batches([]), do: [[]]
  defp batches(ids), do: Enum.chunk_every(ids, @batch)

  defp insert_event(config, event) do
    case config.repo.insert_all(Event, [event],
           on_conflict: :nothing,
           conflict_target: :key,
           prefix: config.prefix
         ) do
      {1, _} -> :ok
      {0, _} -> :duplicate
    end
  end

  defp duplicate(config, opts) do
    {:error, :duplicate, config.repo.get_by!(Event, [key: opts[:key]], prefix: config.prefix)}
  end

  # After the first batch: the news of it, the other batches, the event's
  # count of people.
  defp finish(%{config: config, event: event} = plan, ids, counts, rest) do
    Fanout.notified(config, counts)
    notified = map_size(counts) + Enum.sum(Enum.map(rest, &rest_batch(plan, &1)))
    if notified != length(ids), do: notified(config, event, notified)

    :telemetry.execute([:chime, :notify], %{recipients: notified}, %{
      notifier: plan.notifier,
      event_id: event.id
    })

    config.repo.get!(Event, event.id, prefix: config.prefix)
  end

  # A notification for later: the guard decides now, with the params; the
  # event keeps its people, and a job runs it at its time.
  defp schedule(%{config: config, event: event} = plan, ids, at, opts) do
    ids = ids |> batches() |> Enum.flat_map(&(plan |> guard(&1) |> elem(0)))

    event =
      Map.merge(event, %{
        status: "scheduled",
        scheduled_at: at,
        audience: ids,
        recipients: length(ids)
      })

    result =
      config.repo.transaction(fn ->
        case insert_event(config, event) do
          :ok -> Chime.Jobs.notify(config, event.id, at)
          :duplicate -> config.repo.rollback(:duplicate)
        end
      end)

    case result do
      {:ok, :ok} -> {:ok, config.repo.get!(Event, event.id, prefix: config.prefix)}
      {:error, :duplicate} -> duplicate(config, opts)
    end
  end

  @doc false
  # A scheduled event's time came: claimed (a cancelled one, or one sent
  # already, does nothing), then its people notified as now.
  @spec fire(Config.t(), Ecto.UUID.t(), DateTime.t()) :: :ok
  def fire(%Config{} = config, id, now \\ DateTime.utc_now()) do
    now = Chime.Schema.usec(now)

    result =
      config.repo.transaction(fn ->
        claim =
          from(e in Event, where: e.id == ^id and e.status == "scheduled", select: e)
          |> config.repo.update_all([set: [status: "sent"]], prefix: config.prefix)

        with {1, [event]} <- claim,
             {_plan, _ids, _counts, _rest} = first <- fire_first(config, event, now) do
          first
        else
          _ -> :done
        end
      end)

    case result do
      {:ok, {plan, ids, counts, rest}} -> finish(plan, ids, counts, rest)
      {:ok, :done} -> :ok
    end

    :ok
  end

  defp fire_first(config, %Event{} = event, now) do
    case Event.notifier(event) do
      nil ->
        :done

      _notifier when event.audience == nil ->
        # An audience: its pages, from now.
        from(e in Event, where: e.id == ^event.id)
        |> config.repo.update_all([set: [status: "sending"]], prefix: config.prefix)

        Chime.Jobs.audience(config, event.id, nil)
        :audience

      notifier ->
        ids = event.audience || []
        event = Map.take(event, [:id, :kind, :category, :workspace, :data, :actor, :group_key])
        plan = plan(config, notifier, event, notifier.__chime__(:deliveries), now, [])
        [first | rest] = batches(ids)
        close_groups(plan)
        {plan, ids, batch(plan, first), rest}
    end
  end

  @doc false
  # Cancels an event: one scheduled is not sent; one sent has its
  # deliveries that wait skipped, and with `feed: :remove`, its
  # notifications that hold it alone taken out of the feeds.
  @spec cancel(Config.t(), Event.t(), keyword()) ::
          {:ok, %{deliveries: non_neg_integer(), removed: non_neg_integer()}}
  def cancel(%Config{} = config, %Event{status: status} = event, opts)
      when status in ["scheduled", "sending"] do
    from(e in Event, where: e.id == ^event.id and e.status == ^status)
    |> config.repo.update_all([set: [status: "cancelled"]], prefix: config.prefix)

    # The people an audience told already: as for one sent.
    if status == "sending",
      do: cancel(config, %{event | status: "cancelled"}, opts),
      else: {:ok, %{deliveries: 0, removed: 0}}
  end

  def cancel(%Config{} = config, %Event{status: "scheduled"} = event, _opts) do
    from(e in Event, where: e.id == ^event.id and e.status == "scheduled")
    |> config.repo.update_all([set: [status: "cancelled"]], prefix: config.prefix)

    {:ok, %{deliveries: 0, removed: 0}}
  end

  def cancel(%Config{} = config, %Event{} = event, opts) do
    now = DateTime.utc_now()
    notifications = from(n in Notification, where: n.event_id == ^event.id, select: n.id)

    {:ok, {deliveries, removed}} =
      config.repo.transaction(fn ->
        {deliveries, _} =
          from(d in Delivery,
            where:
              d.notification_id in subquery(notifications) and d.status in ["scheduled", "digest"]
          )
          |> config.repo.update_all(
            [set: [status: "skipped", reason: "the notification was cancelled", updated_at: now]],
            prefix: config.prefix
          )

        {deliveries, remove(config, event, opts[:feed])}
      end)

    {:ok, %{deliveries: deliveries, removed: removed}}
  end

  defp remove(_config, _event, nil), do: 0

  defp remove(config, event, :remove) do
    rows =
      from(n in Notification,
        where: n.event_id == ^event.id and n.count == 1,
        select: {n.id, n.recipient}
      )
      |> config.repo.all(prefix: config.prefix)

    people = rows |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    Counts.lock(config, people)
    ids = Enum.map(rows, &elem(&1, 0))
    config.repo.delete_all(from(n in Notification, where: n.id in ^ids), prefix: config.prefix)

    config
    |> Counts.refresh(people)
    |> Enum.each(fn {recipient, counts} -> Fanout.updated(config, recipient, counts) end)

    length(ids)
  end

  defp rest_batch(%{config: config} = plan, ids) do
    {:ok, counts} = config.repo.transaction(fn -> batch(plan, ids) end)
    Fanout.notified(config, counts)
    map_size(counts)
  end

  # The people the guards let through, on the event.
  defp notified(config, event, n) do
    from(e in Event, where: e.id == ^event.id)
    |> config.repo.update_all([set: [recipients: n]], prefix: config.prefix)
  end

  # A group is a notifier's own, in its workspace: two notifiers with the
  # same key do not join each other's notifications.
  defp group_key(notifier, params, kind, workspace) do
    case notifier.group(params) do
      nil -> nil
      group -> "#{workspace && workspace <> "/"}#{kind}:#{group}"
    end
  end

  defp workspace(notifier, params, opts) do
    case Keyword.fetch(opts, :workspace) do
      {:ok, workspace} -> workspace && to_string(workspace)
      :error -> notifier.workspace(params) |> then(&(&1 && to_string(&1)))
    end
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

  # The ids of the people, once each, from :to or the notifier, but the
  # actor unless the notifier tells them too; and the recipients given
  # whole, by id, for the guards.
  defp recipients(config, notifier, params, opts, actor) do
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

    actor_id = actor && (actor["id"] || actor[:id])

    entries =
      recipients
      |> Enum.map(&Resolver.to_recipient(config.resolver, &1))
      |> Enum.uniq_by(&Resolver.id/1)
      |> Enum.reject(&(Resolver.id(&1) == actor_id and not notifier.__chime__(:notify_actor)))

    {Enum.map(entries, &Resolver.id/1),
     for(%Chime.Recipient{} = r <- entries, into: %{}, do: {r.id, r})}
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

  defp batch(plan, ids) do
    {ids, people} = guard(plan, ids)
    batch(plan, ids, people)
  end

  defp batch(_plan, [], _people), do: %{}

  defp batch(%{config: config} = plan, ids, people) do
    # The people's counts locked first, so that what follows sees what
    # other calls for the same people committed, and they wait for this.
    Counts.lock(config, ids)
    kept = Preferences.stored(config, ids, plan.category.key, plan.event.workspace)

    # Why each person is not in the feed, or nil when they are.
    out_of_feed =
      Map.new(ids, fn id ->
        {setting, at} =
          Preferences.setting(plan.category, plan.required, Map.get(kept, id, %{}), "feed")

        {id, out_of_feed(plan, setting, at, people[id])}
      end)

    in_feed = Map.new(out_of_feed, fn {id, reason} -> {id, plan.feed and reason == nil} end)

    {new, joined} = notifications(plan, ids, in_feed)
    feed_skipped(plan, new, out_of_feed)
    deliveries(plan, new, joined, kept)

    Counts.refresh(config, ids)
  end

  # The people of a batch the notifier's guard (notify?/2) lets through,
  # and the recipients whole when a guard or the feed's conditions need
  # them: those given, else the resolver's. A person the resolver does
  # not give is not notified when there is a guard.
  defp guard(%{guard: false, feed_spec: %{if: [], unless: []}}, ids), do: {ids, %{}}
  defp guard(%{guard: false, feed_spec: nil}, ids), do: {ids, %{}}

  defp guard(plan, ids) do
    missing = Enum.reject(ids, &Map.has_key?(plan.known, &1))

    people =
      if missing == [],
        do: Map.take(plan.known, ids),
        else:
          Map.merge(
            Map.take(plan.known, ids),
            Map.new(plan.config.resolver.recipients(missing), &{&1.id, &1})
          )

    ids =
      if plan.guard,
        do: Enum.filter(ids, &(people[&1] && plan.notifier.notify?(plan.params, people[&1]))),
        else: ids

    {ids, people}
  end

  # Why a person is not in the feed: turned off, or the feed's own
  # conditions, of the notifier's functions; nil when they are. A notifier
  # with no feed has no reason.
  defp out_of_feed(%{feed_spec: nil}, _setting, _at, _recipient), do: nil

  defp out_of_feed(plan, "off", at, _recipient),
    do: Chime.Explain.turned_off(plan.category, "feed", at)

  defp out_of_feed(%{feed_spec: %{if: [], unless: []}}, _setting, _at, _recipient), do: nil
  defp out_of_feed(_plan, _setting, _at, nil), do: "the resolver does not give the person"

  defp out_of_feed(%{feed_spec: spec, notifier: notifier, event: event}, _setting, _at, recipient) do
    Enum.find_value(spec.unless, fn c ->
      condition(notifier, c, event.data, recipient) && "unless #{name(c)}"
    end) ||
      Enum.find_value(spec.if, fn c ->
        !condition(notifier, c, event.data, recipient) && "if #{name(c)} was false"
      end)
  end

  defp name({module, fun}), do: "#{inspect(module)}.#{fun}"
  defp name(fun), do: Atom.to_string(fun)

  # A new notification kept out of the feed has a "feed" delivery,
  # skipped, with the reason, for the log.
  defp feed_skipped(%{feed: false}, _new, _out), do: :ok

  defp feed_skipped(%{config: config, now: now}, new, out) do
    rows =
      for {recipient, id} <- new, reason = out[recipient], reason != nil do
        %{
          id: Ecto.UUID.generate(),
          notification_id: id,
          recipient: recipient,
          channel: "feed",
          status: "skipped",
          reason: reason,
          attempts: 0,
          scheduled_at: now,
          inserted_at: now,
          updated_at: now
        }
      end

    rows
    |> Enum.chunk_every(@batch)
    |> Enum.each(&config.repo.insert_all(Delivery, &1, prefix: config.prefix))
  end

  defp condition(notifier, name, data, recipient) when is_atom(name),
    do: apply(notifier, name, [data, recipient])

  defp condition(_notifier, {module, fun}, data, recipient),
    do: apply(module, fun, [data, recipient])

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
          workspace: event.workspace,
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

    debounce(plan, joined)
  end

  # The deliveries that wait for a group's events and debounce: their time
  # is `:wait` after this event, but no later than `:max_wait` after they
  # were made. Their jobs find the new time when they run (Chime.Deliver).
  defp debounce(%{config: config, channels: channels, now: now}, joined) do
    ids = Enum.map(joined, &elem(&1, 1))

    for %{debounce: true} = channel <- channels, ids != [] do
      at = DateTime.add(now, channel.wait)

      from(d in Delivery,
        where:
          d.notification_id in ^ids and d.channel == ^channel.channel and d.status == "scheduled",
        select: {d.id, d.inserted_at}
      )
      |> config.repo.all(prefix: config.prefix)
      |> Enum.group_by(fn {_id, made} -> capped(at, made, channel.max_wait) end, &elem(&1, 0))
      |> Enum.each(fn {at, ids} ->
        from(d in Delivery, where: d.id in ^ids)
        |> config.repo.update_all([set: [scheduled_at: at]], prefix: config.prefix)
      end)
    end

    :ok
  end

  defp capped(at, _made, nil), do: at
  defp capped(at, made, max), do: Enum.min([at, DateTime.add(made, max)], DateTime)

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
