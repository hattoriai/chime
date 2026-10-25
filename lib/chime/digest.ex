defmodule Chime.Digest do
  @moduledoc ~S"""
  The digests: one email of the notifications of a day or a week, for the
  people who chose `"daily"` or `"weekly"` for a category's email
  (`Chime.Preferences`).

  Such an email does not go at its time: its delivery waits, as
  `"digest"`, with the decisions of then made (the `:unless` and `:if`
  of the notifier, the preferences). Every hour, a job finds the people
  whose digest is due, in their own time zone (`:time_zone` of
  `Chime.Recipient`): at the config's hour (`:at` of `:digest`, 9), every
  day for a daily digest, on `:weekly_on` (Monday) for a weekly one. Each
  person gets one email of all their notifications due, and each delivery
  is then `"digested"`. An hour the job missed (a deploy) is made up at
  the next.

  The time zones need a time zone database (`tz` or `tzdata`) set as
  Elixir's: `config :elixir, :time_zone_database, Tz.TimeZoneDatabase`.
  Without one, every digest is at the hour in UTC.

  ## The email

  Chime writes it from what the feed shows of each notification
  (`c:Chime.Notifier.feed/2`), unless the app gives its own module
  (`email: MyApp.ChimeDigest` in `:digest`):

      defmodule MyApp.ChimeDigest do
        import Swoosh.Email

        def email(recipient, items, period) do
          new()
          |> subject("Your #{period} digest: #{length(items)} notifications")
          |> html_body(MyAppWeb.Emails.digest(recipient: recipient, items: items))
        end
      end

  Each item is `%{notification: %Chime.Notification{}, feed: %{title: ...}}`,
  the newest first, and `period` is `"daily"` or `"weekly"` (`"daily"`
  when both are due). Chime gives the email its `To:`, its `From:` and a
  link to unsubscribe from every email that is not required.
  """

  import Ecto.Query

  alias Chime.{Channels, Config, Delivery, Event, Feed, Recipient}

  require Logger

  # Swoosh is an optional dependency, with the :mailer option.
  @compile {:no_warn_undefined, [Swoosh.Email]}

  @batch 500
  @weekdays ~w(monday tuesday wednesday thursday friday saturday sunday)a

  @doc false
  # The digests due at `now`: for each person with deliveries waiting,
  # those whose time came, in one email.
  @spec run(Config.t(), DateTime.t()) :: :ok
  def run(%Config{mailer: nil}, _now), do: :ok
  def run(%Config{} = config, now), do: run(config, Chime.Schema.usec(now), nil)

  defp run(config, now, after_id) do
    ids =
      from(d in Delivery,
        where: d.status == "digest",
        distinct: true,
        order_by: d.recipient,
        limit: @batch,
        select: d.recipient
      )
      |> after_recipient(after_id)
      |> config.repo.all(prefix: config.prefix)

    if ids != [] do
      people = Map.new(config.resolver.recipients(ids), &{&1.id, &1})
      Enum.each(ids, &digest(config, &1, people[&1], now))
      if length(ids) == @batch, do: run(config, now, List.last(ids))
    end

    :ok
  end

  defp after_recipient(query, nil), do: query
  defp after_recipient(query, id), do: where(query, [d], d.recipient > ^id)

  defp digest(config, id, nil, now) do
    waiting(config, id)
    |> config.repo.update_all(
      [
        set: [
          status: "skipped",
          reason: "the resolver no longer gives the person",
          updated_at: now
        ]
      ],
      prefix: config.prefix
    )
  end

  defp digest(config, id, %Recipient{} = recipient, now) do
    {daily, weekly} = boundaries(config.digest, recipient.time_zone, now)

    due =
      from(d in waiting(config, id),
        where:
          (d.reason == "daily" and d.updated_at < ^daily) or
            (d.reason == "weekly" and d.updated_at < ^weekly),
        preload: [notification: :event]
      )
      |> config.repo.all(prefix: config.prefix)

    cond do
      due == [] ->
        :ok

      recipient.email in [nil, ""] ->
        mark(config, due, "skipped", "the person has no email address", nil, now)

      true ->
        send_digest(config, recipient, due, now)
    end
  end

  defp waiting(_config, id),
    do: from(d in Delivery, where: d.recipient == ^id and d.status == "digest")

  defp send_digest(config, recipient, due, now) do
    period = if Enum.any?(due, &(&1.reason == "daily")), do: "daily", else: "weekly"

    items =
      due
      |> Enum.uniq_by(& &1.notification_id)
      |> Enum.sort_by(& &1.notification.updated_at, {:desc, DateTime})
      |> Enum.map(fn d ->
        n = d.notification

        feed =
          case Event.notifier(n.event) do
            nil -> %{title: n.kind}
            notifier -> Feed.render(notifier, n.event.data, n)
          end

        %{notification: n, feed: feed}
      end)

    email =
      case config.digest.email do
        nil -> default_email(config, items, period)
        module -> module.email(recipient, items, period)
      end

    message = %{recipient: recipient, required: false}

    result =
      email
      |> Channels.Email.address(config, message)
      |> Channels.Email.unsubscribe(config, message, "*")
      |> Channels.Email.send_email(config)

    case result do
      {:ok, ref} -> mark(config, due, "digested", period, ref, now)
      :ok -> mark(config, due, "digested", period, nil, now)
      {:error, reason} -> Logger.warning("Chime could not send a digest: #{inspect(reason)}")
    end
  end

  defp mark(config, deliveries, status, reason, ref, now) do
    ids = Enum.map(deliveries, & &1.id)

    from(d in Delivery, where: d.id in ^ids and d.status == "digest")
    |> config.repo.update_all(
      [set: [status: status, reason: reason, ref: ref, updated_at: now], inc: [attempts: 1]],
      prefix: config.prefix
    )
  end

  @doc false
  # The last daily and weekly digest times at or before `now`, in the time
  # zone (UTC when it is nil or unknown), as UTC.
  @spec boundaries(map(), String.t() | nil, DateTime.t()) :: {DateTime.t(), DateTime.t()}
  def boundaries(digest, time_zone, now) do
    local = local(now, time_zone)
    today = at(DateTime.to_date(local), digest.at, local.time_zone)

    daily =
      if DateTime.compare(today, now) == :gt,
        do: at(Date.add(DateTime.to_date(local), -1), digest.at, local.time_zone),
        else: today

    weekday = Enum.find_index(@weekdays, &(&1 == digest.weekly_on)) + 1
    back = rem(Date.day_of_week(DateTime.to_date(daily)) - weekday + 7, 7)
    weekly = at(Date.add(DateTime.to_date(daily), -back), digest.at, local.time_zone)

    {DateTime.shift_zone!(daily, "Etc/UTC"), DateTime.shift_zone!(weekly, "Etc/UTC")}
  end

  defp local(now, nil), do: now

  defp local(now, time_zone) do
    case DateTime.shift_zone(now, time_zone) do
      {:ok, local} -> local
      {:error, _} -> now
    end
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

  # Chime's own email: the notifications as the feed shows them.
  defp default_email(config, items, period) do
    title =
      if period == "daily",
        do: "Your notifications of the day",
        else: "Your notifications of the week"

    lines =
      Enum.map(items, fn %{feed: feed} ->
        url = link(config, feed[:url])

        Enum.join(
          Enum.filter(
            ["- #{feed[:title]}", feed[:body] && "  #{feed[:body]}", url && "  #{url}"],
            & &1
          ),
          "\n"
        )
      end)

    html =
      Enum.map_join(items, "", fn %{feed: feed} ->
        url = link(config, feed[:url])

        heading =
          if url,
            do: ~s(<a href="#{escape(url)}">#{escape(feed[:title])}</a>),
            else: escape(feed[:title])

        body = if feed[:body], do: "<br>#{escape(feed[:body])}", else: ""
        "<li>#{heading}#{body}</li>"
      end)

    Swoosh.Email.new(
      subject: title,
      text_body: Enum.join([title, "" | lines], "\n"),
      html_body: "<h1>#{escape(title)}</h1><ul>#{html}</ul>"
    )
  end

  defp link(_config, nil), do: nil
  defp link(_config, "http" <> _ = url), do: url
  defp link(%Config{url: nil}, _path), do: nil
  defp link(%Config{url: base}, "/" <> _ = path), do: base <> path
  defp link(_config, _other), do: nil

  defp escape(text),
    do: text |> to_string() |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
