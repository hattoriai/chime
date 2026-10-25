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

  `counts` is `%{unseen: n, unread: n, workspaces: %{id => %{unseen: n,
  unread: n}}}`: the whole feed's, and each workspace's. `Chime.Live` and the JSON API's
  stream are subscribers.
  """

  use Supervisor

  @typedoc "A person's counts: what they have not seen, and not read."
  @type counts :: %{unseen: non_neg_integer(), unread: non_neg_integer()}

  alias Chime.{Config, Counts, Feed, Messages, Notification, Preferences}

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
    * `:workspace` - the workspace it happens in, instead of the
      notifier's `workspace/1` (see the [Workspaces](workspaces.md) guide).
    * `:at` - a time to notify at, instead of now: the event is
      `"scheduled"`, and a job notifies its people then. The guard
      (`notify?/2`) and the people are decided now; the feed, the
      preferences and the channels at its time. `cancel/2` stops it.
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

  @doc ~S"""
  Cancels an event, by its idempotency key or the event:

      Chime.cancel("comment:#{comment.id}")

  A scheduled event (`:at`) is not sent. One sent has its deliveries that
  wait (an email in ten minutes, a digest) skipped, with "the
  notification was cancelled" in the log. With `feed: :remove`, its
  notifications are taken out of the feeds too, but those of a group that
  holds other events. Returns `{:ok, %{deliveries: n, removed: n}}`, or
  `{:error, :not_found}`.
  """
  @spec cancel(String.t() | Chime.Event.t(), keyword()) ::
          {:ok, %{deliveries: non_neg_integer(), removed: non_neg_integer()}}
          | {:error, :not_found}
  def cancel(key_or_event, opts \\ [])

  def cancel(%Chime.Event{} = event, opts), do: Chime.Notify.cancel(Config.get(), event, opts)

  def cancel(key, opts) when is_binary(key) do
    config = Config.get()

    case config.repo.get_by(Chime.Event, [key: key], prefix: config.prefix) do
      nil -> {:error, :not_found}
      event -> Chime.Notify.cancel(config, event, opts)
    end
  end

  @doc """
  A person's feed, the latest first, each notification with its event:
  `Chime.Feed.render/1` gives what it shows.

  Options:

    * `:limit` - how many (20, up to 100).
    * `:before` - the id of a notification: the page after it.
    * `:filter` - `:inbox`, those not archived (the default), `:unread`,
      `:archived` or `:all`.
    * `:workspace` - only the notifications of a workspace.
  """
  @spec feed(String.t(), keyword()) :: [Notification.t()]
  def feed(recipient, opts \\ []) when is_binary(recipient) do
    opts = Keyword.update(opts, :limit, 20, &min(&1, 100))
    Feed.list(Config.get(), recipient, opts)
  end

  @doc """
  A person's counts: `%{unseen: n, unread: n}`, of the notifications of
  their feed not archived, or of a workspace's (`workspace: id`). One row,
  kept as notifications come and go.
  """
  @spec counts(String.t(), keyword()) :: counts()
  def counts(recipient, opts \\ []) when is_binary(recipient),
    do: Counts.get(Config.get(), recipient, opts[:workspace])

  @doc """
  Marks a person's feed as seen: the bell's dot goes. Option `:workspace`,
  only a workspace's. Returns the counts, of the workspace with one.
  """
  @spec mark_seen(String.t(), keyword()) :: counts()
  def mark_seen(recipient, opts \\ []), do: mark(recipient, :seen, :all, opts)

  @doc """
  Marks notifications of a person as read (and seen): a list of ids, or
  `:all`. Option `:workspace`. Returns the counts.
  """
  @spec mark_read(String.t(), [String.t()] | :all, keyword()) :: counts()
  def mark_read(recipient, ids, opts \\ []), do: mark(recipient, :read, ids, opts)

  @doc "Marks notifications of a person as unread. Returns the counts."
  @spec mark_unread(String.t(), [String.t()] | :all, keyword()) :: counts()
  def mark_unread(recipient, ids, opts \\ []), do: mark(recipient, :unread, ids, opts)

  @doc "Archives notifications of a person: out of the inbox. Returns the counts."
  @spec archive(String.t(), [String.t()] | :all, keyword()) :: counts()
  def archive(recipient, ids, opts \\ []), do: mark(recipient, :archive, ids, opts)

  @doc "Brings archived notifications of a person back. Returns the counts."
  @spec unarchive(String.t(), [String.t()] | :all, keyword()) :: counts()
  def unarchive(recipient, ids, opts \\ []), do: mark(recipient, :unarchive, ids, opts)

  defp mark(recipient, action, ids, opts) do
    Config.get()
    |> Feed.mark(recipient, action, ids, opts[:workspace])
    |> Counts.scope(opts[:workspace])
  end

  @doc """
  A person's preferences: for each category of the config, its settings
  by channel (`Chime.Preferences`). Option `:workspace`: the settings in a
  workspace, its own where the person set them.
  """
  @spec preferences(String.t(), keyword()) :: [Preferences.t()]
  def preferences(recipient, opts \\ []),
    do: Preferences.for_recipient(Config.get(), recipient, opts[:workspace])

  @doc """
  Changes a person's setting of a channel for a category: `"on"`,
  `"off"`, or for email `"daily"` or `"weekly"`. Option `:workspace`: for
  that workspace only, over the person's setting for all. See
  `Chime.Preferences`.
  """
  @spec put_preference(
          String.t(),
          String.t() | atom(),
          String.t() | atom(),
          String.t() | atom(),
          keyword()
        ) :: :ok | {:error, atom()}
  def put_preference(recipient, category, channel, setting, opts \\ []) do
    Preferences.put(
      Config.get(),
      recipient,
      to_string(category),
      to_string(channel),
      to_string(setting),
      opts[:workspace] && to_string(opts[:workspace])
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
  and 4 others", in the app's languages (`Chime.Messages`). An app can
  write its own from `notification.actors`, the latest first, and
  `notification.actor_count`.
  """
  @spec actors(Notification.t()) :: String.t()
  def actors(%Notification{actors: actors} = notification) do
    total = max(notification.actor_count, length(actors))

    case Enum.map(actors, &(&1["name"] || &1[:name])) do
      [] ->
        Messages.t("Someone")

      [one] when total == 1 ->
        one

      [one, two] when total == 2 ->
        Messages.t("%{one} and %{two}", one: one, two: two)

      [one | _] ->
        Messages.tn("%{name} and %{count} other", "%{name} and %{count} others", total - 1,
          name: one
        )
    end
  end

  @doc ~S"""
  A link to a notification, for an email or a channel, that reads it in
  the feed when it is opened, then goes to `url` (a path goes on the
  config's `:url`). See `Chime.Links`. Without the config's `:mail_url`
  and `:secret_key_base`, the address itself.

      ~s(<a href="#{Chime.link(notification, "/stories/42")}">Read it</a>)
  """
  @spec link(Notification.t(), String.t()) :: String.t()
  def link(%Notification{} = notification, url) when is_binary(url) do
    config = Config.get()

    Chime.Token.open_url(config, notification.id, notification.recipient, url) ||
      Chime.Links.address(config, url)
  end

  @doc """
  Takes an action of a notification for its person: one of the
  `:actions` of the notifier's `feed/2` (`%{key: "accept", label:
  "Accept"}`), which calls the notifier's `act/3` with the key, the data
  and the notification. When it says `:ok` or `{:ok, url}`, the
  notification keeps the action and is read, and the person's pages are
  told. Returns `{:ok, %{action: key, url: url | nil}}`, or
  `{:error, :not_found | :unknown_action | :already | reason}`.
  """
  @spec act(String.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, %{action: String.t(), url: String.t() | nil}} | {:error, term()}
  def act(recipient, notification_id, action) when is_binary(recipient) and is_binary(action) do
    Chime.Actions.act(Config.get(), recipient, notification_id, action)
  end

  @doc """
  Registers a device of a person, for the `:push` channel: `%{kind:
  "web", token: endpoint, keys: %{"p256dh" => ..., "auth" => ...}}` for
  a browser's subscription, `%{kind: "apns" | "fcm", token: token}` for a
  phone's; and `:name`. A token registered before is the same device, now
  of this person. Errors: `:unknown_kind`, `:invalid_token`,
  `:invalid_subscription`.
  """
  @spec register_device(String.t(), map()) :: {:ok, Chime.Device.t()} | {:error, atom()}
  def register_device(recipient, attrs),
    do: Chime.Devices.register(Config.get(), recipient, attrs)

  @doc "A person's devices, the latest first."
  @spec devices(String.t()) :: [Chime.Device.t()]
  def devices(recipient), do: Chime.Devices.list(Config.get(), recipient)

  @doc "Turns a person's device on or off (`enabled:`), or names it (`name:`)."
  @spec update_device(String.t(), Ecto.UUID.t(), keyword() | map()) ::
          {:ok, Chime.Device.t()} | {:error, :not_found}
  def update_device(recipient, id, changes),
    do: Chime.Devices.update(Config.get(), recipient, id, Map.new(changes))

  @doc "Removes a person's device."
  @spec remove_device(String.t(), Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def remove_device(recipient, id), do: Chime.Devices.remove(Config.get(), recipient, id)

  @doc """
  The address to unsubscribe a person from a category's emails, for the
  footer of a notifier's email; nil without `:mail_url` and
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
