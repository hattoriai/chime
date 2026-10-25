defmodule Chime.Explain do
  @moduledoc """
  Why a person got a notification, or did not: the log of what Chime
  decided, with the reason of each decision.

  Chime chooses not to send many things, on purpose: the person turned
  the channel off, read the notification in the feed before its email's
  time, has no address, or the notifier's condition said no. From the
  outside it looks the same as a failure ("I never got the email"). The
  log tells them apart:

      Chime.explain(notification_id) |> Chime.Explain.format() |> IO.puts()

      2026-10-25 14:02:11Z  new_comment  to user:42  (comments)
      2026-10-25 14:02:11Z  feed      shown
      2026-10-25 14:02:11Z  telegram  skipped    the person has no Telegram chat
      2026-10-25 14:05:40Z  feed      read
      2026-10-25 14:12:11Z  email     skipped    read in the feed at 2026-10-25 14:05:40Z

  The steps are the notification's (it came, an event of its group joined
  it, it was seen, read, archived) and each delivery's, as
  `Chime.Delivery` keeps them. They are kept as long as the notification
  (`:keep_days` of `Chime.Config`).
  """

  import Ecto.Query

  alias Chime.{Config, Delivery, Notification}

  @typedoc "A step of the log."
  @type step :: %{
          at: DateTime.t(),
          channel: String.t(),
          status: String.t(),
          reason: String.t() | nil
        }

  @typedoc "The log of a notification."
  @type t :: %{notification: Notification.t(), steps: [step()]}

  @doc false
  @spec explain(Config.t(), Ecto.UUID.t() | Notification.t()) :: t() | nil
  def explain(config, %Notification{id: id}), do: explain(config, id)

  def explain(%Config{} = config, id) when is_binary(id) do
    query =
      from(n in Notification,
        where: n.id == ^id,
        preload: [:event, deliveries: ^from(d in Delivery, order_by: [d.inserted_at, d.channel])]
      )

    case config.repo.one(query, prefix: config.prefix) do
      nil -> nil
      notification -> %{notification: notification, steps: steps(notification)}
    end
  end

  defp steps(%Notification{} = n) do
    feed = [
      {n.inserted_at, "feed", if(n.in_feed, do: "shown", else: "skipped"),
       if(n.in_feed, do: nil, else: "the person turned off the feed for #{n.category}")},
      n.count > 1 && {n.updated_at, "feed", "grouped", "#{n.count} events of #{n.group_key}"},
      n.seen_at && {n.seen_at, "feed", "seen", nil},
      n.read_at && {n.read_at, "feed", "read", nil},
      n.archived_at && {n.archived_at, "feed", "archived", nil}
    ]

    deliveries =
      Enum.map(n.deliveries, fn d ->
        at = if d.status == "scheduled", do: d.scheduled_at, else: d.updated_at
        {at, d.channel, d.status, delivery_reason(d)}
      end)

    (feed ++ deliveries)
    |> Enum.filter(& &1)
    |> Enum.map(fn {at, channel, status, reason} ->
      %{at: at, channel: channel, status: status, reason: reason}
    end)
    |> Enum.sort_by(& &1.at, DateTime)
  end

  defp delivery_reason(%Delivery{status: "scheduled", scheduled_at: at, reason: nil}),
    do: "waits until #{time(at)}"

  defp delivery_reason(%Delivery{status: "digest", reason: period}),
    do: "waits for the person's #{period} digest"

  defp delivery_reason(%Delivery{status: "digested", reason: period}),
    do: "went in the person's #{period} digest"

  defp delivery_reason(%Delivery{status: "sent", ref: ref}) when is_binary(ref), do: "ref #{ref}"
  defp delivery_reason(%Delivery{reason: reason}), do: reason

  @doc "The log as lines of text, one for each step."
  @spec format(t() | nil) :: String.t()
  def format(nil), do: "no such notification"

  def format(%{notification: n, steps: steps}) do
    head = "#{time(n.inserted_at)}  #{n.kind}  to #{n.recipient}  (#{n.category})"

    lines =
      Enum.map(steps, fn step ->
        [
          time(step.at),
          String.pad_trailing(step.channel, 9),
          String.pad_trailing(step.status, 10),
          step.reason || ""
        ]
        |> Enum.join("  ")
        |> String.trim_trailing()
      end)

    Enum.join([head | lines], "\n")
  end

  @doc false
  def turned_off(category, channel, nil),
    do: "#{channel} is off for #{category.key} by default"

  def turned_off(category, channel, at),
    do:
      "the person turned off #{channel} for #{category.key} on #{Calendar.strftime(at, "%Y-%m-%d")}"

  @doc false
  def read(at), do: "read in the feed at #{time(at)}"

  @doc false
  def seen(at), do: "seen in the feed at #{time(at)}"

  defp time(%DateTime{} = at),
    do: at |> DateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M:%SZ")
end
