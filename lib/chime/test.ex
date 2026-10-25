defmodule Chime.Test do
  @moduledoc ~S"""
  Helpers for the app's tests of its notifications, with no Oban to run
  and no clock to wait for.

      import Chime.Test

      test "a comment notifies the story's followers", %{story: story} do
        follower = user_fixture()
        story |> follow(follower)

        {:ok, comment} = Stories.comment(story, author, "Lovely.")

        notification = assert_notified(MyApp.Notifications.NewComment, to: follower)
        assert %{title: "Ana commented on Tokyo"} = feed(follower) |> hd()

        # The email waits ten minutes, unless the follower reads it first.
        deliver(at: DateTime.add(DateTime.utc_now(), 11, :minute))
        assert_email_sent(subject: "Ana commented on Tokyo")
      end

  Run the app's Oban in the tests with `testing: :manual`, so that the
  deliveries wait for `deliver/1` (with `:inline`, Oban would send them
  at once, before their time), and start Chime with `scheduler: false`.
  The helpers run in the test's process, inside its sandbox: the emails
  of Swoosh's test adapter come to it, for `Swoosh.TestAssertions`.

  A person is given as the app gives them to `Chime.notify/3`: the app's
  user (through the resolver's `recipient/1`), a `Chime.Recipient` or an
  id.
  """

  import Ecto.Query

  alias Chime.{Config, Deliver, Delivery, Digest, Event, Feed, Notification, Resolver}

  @doc """
  Asserts that a notifier notified a person, and returns their
  notification (with its event). Options:

    * `:to` - the person (required).
    * `:data` - a map the event's data must contain: `%{"story" => "Tokyo"}`.
  """
  @spec assert_notified(module(), keyword()) :: Notification.t()
  def assert_notified(notifier, opts) do
    case notified(notifier, opts) do
      [notification | _] ->
        notification

      [] ->
        raise ExUnit.AssertionError,
          message:
            "expected #{inspect(notifier)} to notify #{recipient_id(opts[:to])}" <>
              if(opts[:data], do: " with #{inspect(opts[:data])}", else: "") <>
              ", but it did not. Their notifications: " <>
              inspect(Enum.map(all(recipient_id(opts[:to])), &{&1.kind, &1.event.data}))
    end
  end

  @doc "Asserts that a notifier did not notify a person (same options)."
  @spec refute_notified(module(), keyword()) :: :ok
  def refute_notified(notifier, opts) do
    case notified(notifier, opts) do
      [] ->
        :ok

      [notification | _] ->
        raise ExUnit.AssertionError,
          message:
            "expected #{inspect(notifier)} not to notify #{recipient_id(opts[:to])}, " <>
              "but it did: #{inspect(notification.event.data)}"
    end
  end

  defp notified(notifier, opts) do
    to = recipient_id(Keyword.fetch!(opts, :to))
    name = inspect(notifier)

    to
    |> all()
    |> Enum.filter(&(&1.event.notifier == name and subset?(opts[:data], &1.event.data)))
  end

  defp subset?(nil, _data), do: true

  defp subset?(expected, data),
    do: Enum.all?(expected, fn {k, v} -> Map.get(data, to_string(k)) == v end)

  defp all(recipient) do
    config = Config.get()

    from(n in Notification,
      where: n.recipient == ^recipient,
      order_by: [desc: n.updated_at],
      preload: :event
    )
    |> config.repo.all(prefix: config.prefix)
  end

  @doc """
  A person's feed as the JSON API gives it: a map for each notification,
  with its `:title`, `:body`, `:url`, `:count`, `:actors`, `:read`... The
  options of `Chime.feed/2`.
  """
  @spec feed(term(), keyword()) :: [map()]
  def feed(recipient, opts \\ []) do
    recipient |> recipient_id() |> Chime.feed(opts) |> Enum.map(&Feed.json/1)
  end

  @doc """
  Runs the deliveries whose time came, in the test's process, as their
  jobs would, and returns them as they are after. Options:

    * `:at` - the time (now): `deliver(at: DateTime.add(DateTime.utc_now(), 11, :minute))`
      runs those of the next ten minutes too.
    * `:to` - only a person's.
    * `:channel` - only a channel's (`"email"`).
    * `:last_attempt` - whether a channel's error fails the delivery
      (`true`), as on its last attempt, or leaves it for another (`false`).
  """
  @spec deliver(keyword()) :: [Delivery.t()]
  def deliver(opts \\ []) do
    config = Config.get()
    at = Keyword.get_lazy(opts, :at, &DateTime.utc_now/0)

    ids =
      from(d in Delivery,
        where: d.status == "scheduled" and d.scheduled_at <= ^at,
        order_by: [d.scheduled_at, d.inserted_at],
        select: d.id
      )
      |> only(:recipient, opts[:to] && recipient_id(opts[:to]))
      |> only(:channel, opts[:channel] && to_string(opts[:channel]))
      |> config.repo.all(prefix: config.prefix)

    Enum.each(ids, &Deliver.perform(config, &1, Keyword.get(opts, :last_attempt, true), at))
    config.repo.all(from(d in Delivery, where: d.id in ^ids), prefix: config.prefix)
  end

  defp only(query, _field, nil), do: query
  defp only(query, field, value), do: where(query, [d], field(d, ^field) == ^value)

  @doc """
  A person's deliveries, the latest first: `[%Chime.Delivery{}]`. Option
  `:channel`.
  """
  @spec deliveries(term(), keyword()) :: [Delivery.t()]
  def deliveries(recipient, opts \\ []) do
    config = Config.get()

    from(d in Delivery,
      where: d.recipient == ^recipient_id(recipient),
      order_by: [desc: d.inserted_at]
    )
    |> only(:channel, opts[:channel] && to_string(opts[:channel]))
    |> config.repo.all(prefix: config.prefix)
  end

  @doc """
  Sends the scheduled notifications (`Chime.notify/3` with `:at`) whose
  time came by `at` (now), as their jobs would.
  """
  @spec run_scheduled(DateTime.t()) :: :ok
  def run_scheduled(at \\ DateTime.utc_now()) do
    config = Config.get()

    from(e in Event, where: e.status == "scheduled" and e.scheduled_at <= ^at, select: e.id)
    |> config.repo.all(prefix: config.prefix)
    |> Enum.each(&Chime.Notify.fire(config, &1, at))
  end

  @doc """
  Goes through the audiences being sent (`c:Chime.Notifier.audience/1`),
  every page, as their jobs would.
  """
  @spec run_audiences() :: :ok
  def run_audiences do
    config = Config.get()

    case config.repo.all(from(e in Event, where: e.status == "sending"), prefix: config.prefix) do
      [] ->
        :ok

      events ->
        Enum.each(events, &Chime.Notify.page(config, &1.id, &1.cursor))
        run_audiences()
    end
  end

  @doc """
  Sends the digests due at a time (now), as the hourly job would: for a
  daily digest at 9:00, a time after 9:00 the day after the notification.
  """
  @spec run_digests(DateTime.t()) :: :ok
  def run_digests(at \\ DateTime.utc_now()), do: Digest.run(Config.get(), at)

  @doc "The log of a notification, as text (`Chime.Explain.format/1`)."
  @spec explain(Notification.t() | Ecto.UUID.t()) :: String.t()
  def explain(notification), do: notification |> Chime.explain() |> Chime.Explain.format()

  @doc "The events a notifier made, the latest first."
  @spec events(module()) :: [Event.t()]
  def events(notifier) do
    config = Config.get()

    from(e in Event, where: e.notifier == ^inspect(notifier), order_by: [desc: e.inserted_at])
    |> config.repo.all(prefix: config.prefix)
  end

  defp recipient_id(nil), do: raise(ArgumentError, "give the person, as :to")

  defp recipient_id(term),
    do: Config.get().resolver |> Resolver.to_recipient(term) |> Resolver.id()
end
