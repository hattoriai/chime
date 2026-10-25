defmodule Chime.Deliver do
  @moduledoc false
  # A delivery's time came: what is decided then, and the channel. Every
  # outcome is written on the delivery, with its reason, for the log.

  import Ecto.Query

  alias Chime.{Config, Delivery, Event, Explain, Message, Messages, Preferences}

  require Logger

  @doc false
  # Decides and sends one delivery. `last?` is whether this is the last
  # attempt: a channel's error then fails it, else Oban tries again.
  @spec perform(Config.t(), Ecto.UUID.t(), boolean(), DateTime.t()) :: :ok | {:error, term()}
  def perform(%Config{} = config, id, last?, now \\ DateTime.utc_now()) do
    now = Chime.Schema.usec(now)
    query = from(d in Delivery, where: d.id == ^id, preload: [notification: :event])

    case config.repo.one(query, prefix: config.prefix) do
      %Delivery{status: "scheduled"} = delivery ->
        # A delivery whose time was moved later (a debounce, a rule) waits
        # for its new time, with a job then.
        if DateTime.diff(delivery.scheduled_at, now) > 1,
          do: Chime.Jobs.deliveries(config, [delivery]),
          else: try_decide(config, delivery, last?, now)

      _done ->
        :ok
    end
  end

  # A delivery that raises on its last attempt is failed, with the error,
  # so that it does not wait for ever (and hold its group's place).
  defp try_decide(config, delivery, last?, now) do
    decide(config, delivery, last?, now)
  rescue
    error ->
      if last? do
        finish(
          config,
          %{delivery | attempts: delivery.attempts + 1},
          "failed",
          Exception.message(error),
          nil,
          now
        )
      end

      reraise error, __STACKTRACE__
  end

  defp decide(config, %Delivery{notification: notification} = delivery, last?, now) do
    event = notification.event

    with {:ok, notifier} <- notifier(event),
         {:ok, spec} <- spec(notifier, delivery.channel),
         {:ok, recipient} <- recipient(config, delivery.recipient),
         {:ok, category, required?} <- category(config, notifier, event),
         {:ok, setting} <- preference(config, category, required?, delivery),
         :ok <- conditions(notifier, spec, event.data, recipient, notification) do
      message = %Message{
        channel: delivery.channel,
        notifier: notifier,
        kind: event.kind,
        category: event.category,
        data: event.data,
        recipient: recipient,
        notification: notification,
        required: required?
      }

      if setting in ["daily", "weekly"] and delivery.channel == "email",
        do: finish(config, delivery, "digest", setting, nil, now),
        else: by_the_rules(config, spec, delivery, message, last?, now)
    else
      {:skip, reason} -> finish(config, delivery, "skipped", reason, nil, now)
    end
  end

  defp notifier(event) do
    case Event.notifier(event) do
      nil -> {:skip, "the notifier #{event.notifier} no longer exists"}
      notifier -> {:ok, notifier}
    end
  end

  defp spec(notifier, channel) do
    case Enum.find(notifier.__chime__(:deliveries), &(&1.channel == channel)) do
      nil -> {:skip, "#{inspect(notifier)} no longer delivers by #{channel}"}
      spec -> {:ok, spec}
    end
  end

  defp recipient(config, id) do
    case Enum.find(config.resolver.recipients([id]), &(&1.id == id)) do
      nil -> {:skip, "the resolver no longer gives the person"}
      recipient -> {:ok, recipient}
    end
  end

  defp category(config, notifier, event) do
    category = Config.category(config, event.category)
    {:ok, category, notifier.__chime__(:required) or category.required}
  rescue
    ArgumentError -> {:skip, "the category #{event.category} is no longer in the config"}
  end

  defp preference(config, category, required?, delivery) do
    kept =
      Preferences.stored(
        config,
        [delivery.recipient],
        category.key,
        delivery.notification.workspace
      )

    case Preferences.setting(
           category,
           required?,
           Map.get(kept, delivery.recipient, %{}),
           delivery.channel
         ) do
      {"off", at} -> {:skip, Explain.turned_off(category, delivery.channel, at)}
      {setting, _at} -> {:ok, setting}
    end
  end

  defp conditions(notifier, spec, data, recipient, notification) do
    reason =
      Enum.find_value(spec.unless, &unless_reason(&1, notifier, data, recipient, notification)) ||
        Enum.find_value(spec.if, &if_reason(&1, notifier, data, recipient))

    if reason, do: {:skip, reason}, else: :ok
  end

  defp unless_reason(:read, _notifier, _data, _recipient, notification),
    do: notification.read_at && Explain.read(notification.read_at)

  defp unless_reason(:seen, _notifier, _data, _recipient, notification),
    do: notification.seen_at && Explain.seen(notification.seen_at)

  defp unless_reason(condition, notifier, data, recipient, _notification),
    do: call(notifier, condition, data, recipient) && "unless #{name(condition)}"

  defp if_reason(condition, notifier, data, recipient),
    do: !call(notifier, condition, data, recipient) && "if #{name(condition)} was false"

  defp call(notifier, name, data, recipient) when is_atom(name),
    do: apply(notifier, name, [data, recipient])

  defp call(_notifier, {module, fun}, data, recipient), do: apply(module, fun, [data, recipient])

  defp name({module, fun}), do: "#{inspect(module)}.#{fun}"
  defp name(fun), do: Atom.to_string(fun)

  defp dispatch(config, delivery, message, last?, now) do
    {module, opts} = Config.channel(config, delivery.channel)
    attempts = delivery.attempts + 1

    result =
      :telemetry.span([:chime, :deliver], %{channel: delivery.channel, kind: message.kind}, fn ->
        # In the person's language: the notifier's words and Chime's.
        result =
          Messages.with_locale(message.recipient.locale, fn -> module.deliver(message, opts) end)

        {result, %{channel: delivery.channel, kind: message.kind, result: result}}
      end)

    delivery = %{delivery | attempts: attempts}

    case result do
      :ok ->
        finish(config, delivery, "sent", nil, nil, now)

      {:ok, ref} ->
        finish(config, delivery, "sent", nil, ref && to_string(ref), now)

      {:skip, reason} ->
        finish(config, delivery, "skipped", to_string(reason), nil, now)

      {:error, reason} when last? ->
        Logger.warning("Chime could not deliver by #{delivery.channel}: #{inspect(reason)}")
        finish(config, delivery, "failed", inspect(reason), nil, now)
        {:error, reason}

      {:error, reason} ->
        # Waits for Oban's next attempt, with the error of this one.
        update(config, delivery, %{reason: "attempt #{attempts}: #{inspect(reason)}"}, now)
        {:error, reason}
    end
  end

  # Sent, unless a rule holds it for later (Chime.Rules).
  defp by_the_rules(config, spec, delivery, message, last?, now) do
    case Chime.Rules.check(config, spec, delivery, message.recipient, message.required, now) do
      :ok -> dispatch(config, delivery, message, last?, now)
      {:later, at, reason} -> later(config, delivery, at, reason, now)
    end
  end

  # Held by a rule: the same delivery, at its new time, with a job then.
  defp later(config, delivery, at, reason, now) do
    from(d in Delivery, where: d.id == ^delivery.id and d.status == "scheduled")
    |> config.repo.update_all([set: [scheduled_at: at, reason: reason, updated_at: now]],
      prefix: config.prefix
    )

    Chime.Jobs.deliveries(config, [%{id: delivery.id, scheduled_at: at}])
    :ok
  end

  defp finish(config, delivery, status, reason, ref, now) do
    update(
      config,
      delivery,
      %{status: status, reason: reason && String.slice(reason, 0, 500), ref: ref},
      now
    )

    :ok
  end

  defp update(config, %Delivery{} = delivery, changes, now) do
    changes = Map.merge(changes, %{attempts: delivery.attempts, updated_at: now})

    from(d in Delivery, where: d.id == ^delivery.id and d.status == "scheduled")
    |> config.repo.update_all([set: Map.to_list(changes)], prefix: config.prefix)
  end
end
