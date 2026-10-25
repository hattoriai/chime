defmodule Chime do
  @moduledoc """
  Chime is notifications for Phoenix: something happens in the app, and
  Chime tells the people it concerns, in the app's feed (the bell), by
  email and by the app's own channels, as each person wants.

  Add Chime to the app's supervision tree, after the repo, the PubSub and
  Oban (`Chime.Config` has the options):

      {Chime, repo: MyApp.Repo, pubsub: MyApp.PubSub, resolver: MyApp.ChimeResolver}

  Write a `Chime.Notifier` for each kind of notification, and send one:

      Chime.notify(MyApp.Notifications.NewComment, %{comment: comment})

  The functions of this module read and change a person's feed, by the
  person's id: `feed/2`, `counts/1`, `mark_seen/1`, `mark_read/2`,
  `mark_unread/2`, `archive/2`, `unarchive/2`; their preferences:
  `preferences/1`, `put_preference/4`; and the log of what was decided:
  `explain/1`.

  Start with the [Quickstart](quickstart.md).

  ## Live

  `subscribe/1` subscribes the caller to a person's topic, on the app's
  PubSub. It receives:

    * `{Chime, :notified, counts}` - a notification came, or an event
      joined one of their groups;
    * `{Chime, :updated, counts}` - they saw, read or archived
      notifications, in another tab or on another device.

  `counts` is `%{unseen: n, unread: n}`. `Chime.Live` and the JSON API's
  stream are subscribers.
  """

  use Supervisor

  @typedoc "A person's counts: what they have not seen, and not read."
  @type counts :: %{unseen: non_neg_integer(), unread: non_neg_integer()}

  alias Chime.{Config, Counts, Feed, Notification, Preferences}

  @doc "Starts Chime with the options of `Chime.Config`."
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @impl Supervisor
  def init(opts) do
    config = Config.new(opts)
    Config.put(config)

    children = [
      {Chime.Fanout, config},
      config.scheduler &&
        Supervisor.child_spec({Task, fn -> Chime.Jobs.boot(config) end}, id: Chime.Jobs)
    ]

    Supervisor.init(Enum.filter(children, & &1), strategy: :one_for_one)
  end

  @doc ~S"""
  Notifies the people of an event, by the notifier's channels.

  The notifier's `recipients/1` says who, unless `:to` does. Each person
  gets a notification in their feed at once (unless they turned the feed
  off for the category), or the event joins their open notification of
  its group; each other channel is a delivery, which goes at its time as
  an Oban job, in the same transaction.

  Options:

    * `:to` - the people, instead of the notifier's `recipients/1`: the
      app's users, `Chime.Recipient`s or ids.
    * `:key` - an idempotency key: a second call with the same key does
      nothing, and returns `{:error, :duplicate, event}`. Give one when
      the call may run twice (a retried job): `"comment:#{comment.id}"`.

  Returns `{:ok, %Chime.Event{}}`. For many people, it works a batch of
  1000 at a time, each its own transaction: call it from a job of the
  app for an event to everyone.
  """
  @spec notify(module(), term(), keyword()) ::
          {:ok, Chime.Event.t()} | {:error, :duplicate, Chime.Event.t()}
  def notify(notifier, params, opts \\ []) when is_atom(notifier) do
    Chime.Notify.run(Config.get(), notifier, params, opts)
  end

  @doc """
  A person's feed, the latest first, each notification with its event:
  `Chime.Feed.render/1` gives what it shows.

  Options:

    * `:limit` - how many (20, up to 100).
    * `:before` - the id of a notification: the page after it.
    * `:filter` - `:inbox`, those not archived (the default), `:unread`,
      `:archived` or `:all`.
  """
  @spec feed(String.t(), keyword()) :: [Notification.t()]
  def feed(recipient, opts \\ []) when is_binary(recipient) do
    opts = Keyword.update(opts, :limit, 20, &min(&1, 100))
    Feed.list(Config.get(), recipient, opts)
  end

  @doc """
  A person's counts: `%{unseen: n, unread: n}`, of the notifications of
  their feed not archived. One row, kept as notifications come and go.
  """
  @spec counts(String.t()) :: counts()
  def counts(recipient) when is_binary(recipient), do: Counts.get(Config.get(), recipient)

  @doc "Marks a person's feed as seen: the bell's dot goes. Returns the counts."
  @spec mark_seen(String.t()) :: counts()
  def mark_seen(recipient), do: Feed.mark(Config.get(), recipient, :seen, :all)

  @doc """
  Marks notifications of a person as read (and seen): a list of ids, or
  `:all`. Returns the counts.
  """
  @spec mark_read(String.t(), [String.t()] | :all) :: counts()
  def mark_read(recipient, ids), do: Feed.mark(Config.get(), recipient, :read, ids)

  @doc "Marks notifications of a person as unread. Returns the counts."
  @spec mark_unread(String.t(), [String.t()] | :all) :: counts()
  def mark_unread(recipient, ids), do: Feed.mark(Config.get(), recipient, :unread, ids)

  @doc "Archives notifications of a person: out of the inbox. Returns the counts."
  @spec archive(String.t(), [String.t()] | :all) :: counts()
  def archive(recipient, ids), do: Feed.mark(Config.get(), recipient, :archive, ids)

  @doc "Brings archived notifications of a person back. Returns the counts."
  @spec unarchive(String.t(), [String.t()] | :all) :: counts()
  def unarchive(recipient, ids), do: Feed.mark(Config.get(), recipient, :unarchive, ids)

  @doc """
  A person's preferences: for each category of the config, its settings
  by channel (`Chime.Preferences`).
  """
  @spec preferences(String.t()) :: [Preferences.t()]
  def preferences(recipient), do: Preferences.for_recipient(Config.get(), recipient)

  @doc """
  Changes a person's setting of a channel for a category: `"on"`,
  `"off"`, or for email `"daily"` or `"weekly"`. See `Chime.Preferences`.
  """
  @spec put_preference(String.t(), String.t() | atom(), String.t() | atom(), String.t() | atom()) ::
          :ok | {:error, atom()}
  def put_preference(recipient, category, channel, setting) do
    Preferences.put(
      Config.get(),
      recipient,
      to_string(category),
      to_string(channel),
      to_string(setting)
    )
  end

  @doc """
  The log of a notification: when it came, what each channel decided
  and why. See `Chime.Explain`.
  """
  @spec explain(Ecto.UUID.t() | Notification.t()) :: Chime.Explain.t() | nil
  def explain(notification), do: Chime.Explain.explain(Config.get(), notification)

  @doc "Subscribes the caller to a person's live news (see Live, above)."
  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(recipient) when is_binary(recipient) do
    Phoenix.PubSub.subscribe(Config.get().pubsub, topic(recipient))
  end

  @doc false
  @spec topic(String.t()) :: String.t()
  def topic(recipient), do: "chime:" <> recipient

  @doc """
  Who did a notification's events, in words: "Ana", "Ana and Rui", "Ana
  and 4 others". In English; an app in other languages writes its own,
  from `notification.actors`, the latest first.
  """
  @spec actors(Notification.t()) :: String.t()
  def actors(%Notification{actors: actors}) do
    case Enum.map(actors, &(&1["name"] || &1[:name])) do
      [] -> "Someone"
      [one] -> one
      [one, two] -> "#{one} and #{two}"
      [one | rest] -> "#{one} and #{length(rest)} others"
    end
  end

  @doc """
  The address to unsubscribe a person from a category's emails, for the
  footer of a notifier's email; nil without `:unsubscribe_url` and
  `:secret_key_base` in the config.
  """
  @spec unsubscribe_url(Chime.Recipient.t() | String.t(), Notification.t() | String.t()) ::
          String.t() | nil
  def unsubscribe_url(recipient, %Notification{category: category}),
    do: unsubscribe_url(recipient, category)

  def unsubscribe_url(recipient, category) when is_binary(category) do
    Chime.Token.unsubscribe_url(Config.get(), Chime.Resolver.id(recipient), category)
  end
end
