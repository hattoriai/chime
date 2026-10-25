defmodule Chime.Rules do
  @moduledoc false
  # The rules that hold a delivery for later, decided at its time: the
  # person's quiet hours, the notifier's throttle of a group, the config's
  # limit of a channel. {:later, at, reason}, or :ok. Required
  # notifications are not held.

  import Ecto.Query

  alias Chime.{Config, Delivery, Notification, Recipient}

  @doc false
  @spec check(Config.t(), map(), Delivery.t(), Recipient.t(), boolean(), DateTime.t()) ::
          :ok | {:later, DateTime.t(), String.t()}
  def check(_config, _spec, _delivery, _recipient, true = _required?, _now), do: :ok

  def check(config, spec, delivery, recipient, false, now) do
    with :ok <- quiet(config, spec, recipient, now),
         :ok <- throttle(config, spec, delivery, now) do
      under_limit(config, delivery, now)
    end
  end

  # -- quiet hours ---------------------------------------------------------

  defp quiet(_config, %{quiet: false}, _recipient, _now), do: :ok

  defp quiet(config, _spec, recipient, now) do
    case hours(config, recipient) do
      nil ->
        :ok

      {from, to} ->
        local = local(now, recipient.time_zone)

        if quiet?(local.hour, from, to) do
          until = next(local, to)

          {:later, DateTime.shift_zone!(until, "Etc/UTC") |> Chime.Schema.usec(),
           "quiet hours until #{pad(to)}:00"}
        else
          :ok
        end
    end
  end

  defp hours(_config, %Recipient{quiet_hours: false}), do: nil
  defp hours(_config, %Recipient{quiet_hours: {_, _} = hours}), do: hours
  defp hours(%Config{quiet_hours: hours}, _recipient) when hours in [nil, false], do: nil
  defp hours(%Config{quiet_hours: hours}, _recipient), do: hours

  # 22 to 8 is the night, over midnight; 1 to 6, within a day.
  defp quiet?(hour, from, to) when from > to, do: hour >= from or hour < to
  defp quiet?(hour, from, to), do: hour >= from and hour < to

  # The next time it is `hour` o'clock, local.
  defp next(local, hour) do
    today = at(DateTime.to_date(local), hour, local.time_zone)

    if DateTime.compare(today, local) == :gt,
      do: today,
      else: at(Date.add(DateTime.to_date(local), 1), hour, local.time_zone)
  end

  defp at(date, hour, time_zone) do
    naive = NaiveDateTime.new!(date, Time.new!(hour, 0, 0))

    case DateTime.from_naive(naive, time_zone) do
      {:ok, at} -> at
      {:ambiguous, first, _second} -> first
      {:gap, _before, just_after} -> just_after
      {:error, _} -> DateTime.from_naive!(naive, "Etc/UTC")
    end
  end

  defp local(now, nil), do: now

  defp local(now, time_zone) do
    case DateTime.shift_zone(now, time_zone) do
      {:ok, local} -> local
      {:error, _} -> now
    end
  end

  defp pad(hour), do: hour |> Integer.to_string() |> String.pad_leading(2, "0")

  # -- throttle ------------------------------------------------------------

  defp throttle(_config, %{throttle: nil}, _delivery, _now), do: :ok

  defp throttle(config, %{throttle: seconds}, delivery, now) do
    since = DateTime.add(now, -seconds)
    n = delivery.notification

    query =
      from(d in Delivery,
        join: o in Notification,
        on: o.id == d.notification_id,
        where:
          d.recipient == ^delivery.recipient and d.channel == ^delivery.channel and
            d.status == "sent" and d.updated_at > ^since and d.id != ^delivery.id,
        select: max(d.updated_at)
      )

    query =
      if n.group_key,
        do: where(query, [_d, o], o.group_key == ^n.group_key),
        else: where(query, [_d, o], o.kind == ^n.kind)

    case config.repo.one(query, prefix: config.prefix) do
      nil ->
        :ok

      last ->
        {:later, DateTime.add(last, seconds),
         "throttled: one #{delivery.channel} in #{minutes(seconds)}"}
    end
  end

  # -- limits --------------------------------------------------------------

  defp under_limit(%Config{limits: limits} = config, delivery, now) do
    case Map.get(limits, delivery.channel) do
      nil ->
        :ok

      {n, seconds} ->
        since = DateTime.add(now, -seconds)

        sent =
          from(d in Delivery,
            where:
              d.recipient == ^delivery.recipient and d.channel == ^delivery.channel and
                d.status == "sent" and d.updated_at > ^since,
            order_by: [desc: d.updated_at],
            limit: ^n,
            select: d.updated_at
          )
          |> config.repo.all(prefix: config.prefix)

        if length(sent) < n do
          :ok
        else
          {:later, DateTime.add(List.last(sent), seconds),
           "the limit: #{n} by #{delivery.channel} in #{minutes(seconds)}"}
        end
    end
  end

  defp minutes(seconds) when rem(seconds, 86_400) == 0, do: "#{div(seconds, 86_400)} d"
  defp minutes(seconds) when rem(seconds, 3600) == 0, do: "#{div(seconds, 3600)} h"
  defp minutes(seconds) when rem(seconds, 60) == 0, do: "#{div(seconds, 60)} min"
  defp minutes(seconds), do: "#{seconds} s"
end
