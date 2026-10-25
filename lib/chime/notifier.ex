defmodule Chime.Notifier do
  @moduledoc ~S"""
  A kind of notification of the app: who it goes to, by which channels,
  and what it says in each. Chime has none of its own; the app writes one
  module for each kind it has.

      defmodule MyApp.Notifications.NewComment do
        use Chime.Notifier, category: :comments, group_window: {10, :minute}

        deliver :feed
        deliver :email, wait: {10, :minute}, unless: :read
        deliver :telegram, if: :telegram?

        @impl true
        def recipients(%{comment: comment}),
          do: MyApp.Stories.followers(comment.story_id) -- [comment.author]

        @impl true
        def data(%{comment: comment}) do
          %{"story_id" => comment.story_id, "story" => comment.story.title, "text" => comment.text}
        end

        @impl true
        def actor(%{comment: comment}),
          do: %{"id" => "user:#{comment.author.id}", "name" => comment.author.name}

        @impl true
        def group(%{comment: comment}), do: "story:#{comment.story_id}"

        @impl true
        def feed(data, notification) do
          %{
            title: "#{Chime.actors(notification)} commented on #{data["story"]}",
            body: data["text"],
            url: "/stories/#{data["story_id"]}"
          }
        end

        @impl true
        def email(data, _recipient, notification) do
          Swoosh.Email.new(
            subject: "#{Chime.actors(notification)} commented on #{data["story"]}",
            text_body: data["text"]
          )
        end

        def telegram?(_data, recipient), do: recipient.data.telegram_chat != nil
      end

  Then, where the comment is made:

      Chime.notify(MyApp.Notifications.NewComment, %{comment: comment},
        key: "comment:#{comment.id}")

  ## Options of `use`

    * `:category` - the category of `Chime.Config` it is of, which the
      preferences turn on and off (required).
    * `:kind` - its name in the JSON API and the components
      (`"new_comment"` for `MyApp.Notifications.NewComment`).
    * `:required` - it goes whatever the person's preferences, and its
      emails have no link to unsubscribe (`false`; a category of
      `required: true` makes all its notifiers so).
    * `:notify_actor` - whether the person who did it (`c:actor/1`) is
      notified too, when they are among the recipients (`false`: nobody is
      told of what they did).
    * `:group_window` - with `c:group/1`: how long a notification stays
      open to the events of its group, from the first (`{1, :hour}`).

  ## Channels

  `deliver/2` declares a channel, in the order they go: `:feed`, the
  bell and its list in the app (decided when the notification comes, with
  `:if` and `:unless` of the notifier's functions only); `:email`, through the app's mailer; or
  one of the app's `:channels` (`Chime.Channel`). Options:

    * `:wait` - how long after the notification it goes: `{10, :minute}`
      (`:second`, `:minute`, `:hour`, `:day`) or a number of seconds.
      What is decided then (the conditions, the preferences) is decided
      at that time.
    * `:unless` - it does not go if: `:read` (the person read it in the
      feed meanwhile), `:seen` (they saw it in the feed), or the name of a
      function of the notifier, `(data, recipient) -> boolean`. A list is
      any of them.
    * `:if` - it goes only if this function of the notifier,
      `(data, recipient) -> boolean`, says so; or `{module, function}`.

  ## What it says

  The feed and the emails are made from `c:data/1`, kept on the event as
  JSON when the notification comes, and rendered when they are shown: in
  the person's language, as the app's words are then, and with the count
  of a group ("Ana and 4 others"). Each channel calls its function of
  the notifier: `c:feed/2`, `c:email/3`, and, for an app's channel, the
  function of its name (`telegram/3`) when there is one.

  See the [Notifiers](notifiers.md) guide.
  """

  @typedoc "The params given to `Chime.notify/3`."
  @type params :: term()

  @typedoc "What the feed shows of a notification."
  @type feed :: %{
          required(:title) => String.t(),
          optional(:body) => String.t() | nil,
          optional(:url) => String.t() | nil,
          optional(:icon) => String.t() | nil,
          optional(atom()) => term()
        }

  @doc """
  Who it goes to: the app's users (turned into recipients by
  `c:Chime.Resolver.recipient/1`), `Chime.Recipient`s, or their ids.
  `Chime.notify/3` with `:to` does not call it.
  """
  @callback recipients(params()) :: [term()]

  @doc """
  What is kept of the params, as JSON (a map of strings, numbers, lists
  and maps), for the feed and the channels to render from. By default,
  the params themselves, as JSON.
  """
  @callback data(params()) :: map()

  @doc ~s|Who did it: `%{"id" => ..., "name" => ...}`, or nil (nil).|
  @callback actor(params()) :: map() | nil

  @doc """
  The group its notifications join: a string, such as `"story:42"`, or
  nil. A person's notification of the same group, unread and within the
  `:group_window`, takes the new event instead of a new notification: its
  count goes up, its actors take the new one, and it comes to the top of
  the feed. By default, nil: no groups.
  """
  @callback group(params()) :: String.t() | nil

  @doc """
  The workspace it happens in: the id of a team, an organisation, a
  collective of the app's, as a string, or nil (nil). Its notifications
  are of that workspace: a feed, counts and preferences can be of one
  workspace (see the [Workspaces](workspaces.md) guide). `Chime.notify/3`
  with `:workspace` gives it instead.
  """
  @callback workspace(params()) :: String.t() | nil

  @doc """
  Whether a person is notified at all: the guard of the app's rules, such
  as "may this person read the channel?", checked for each person when
  the notification comes, with the params of `Chime.notify/3` and the
  `Chime.Recipient` (as the resolver gives them). A person it says no to
  gets nothing, by any channel. By default, everyone.
  """
  @callback notify?(params(), Chime.Recipient.t()) :: boolean()

  @doc "What the feed shows: `:title`, and `:body`, `:url` and `:icon`."
  @callback feed(data :: map(), Chime.Notification.t()) :: feed()

  @doc """
  The email: a `Swoosh.Email` with its subject and body. Chime gives it
  its `To:` and, unless the notification is required, the link and the
  headers to unsubscribe; its `From:` is the config's unless it has one.
  """
  @callback email(data :: map(), Chime.Recipient.t(), Chime.Notification.t()) :: struct()

  @optional_callbacks recipients: 1,
                      data: 1,
                      actor: 1,
                      group: 1,
                      workspace: 1,
                      notify?: 2,
                      feed: 2,
                      email: 3

  @units %{second: 1, minute: 60, hour: 3600, day: 86_400}

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Chime.Notifier

      import Chime.Notifier, only: [deliver: 1, deliver: 2]

      Module.register_attribute(__MODULE__, :chime_deliveries, accumulate: true)
      @chime_config Chime.Notifier.__config__(__MODULE__, opts)

      @impl Chime.Notifier
      def data(params), do: Chime.Notifier.json!(__MODULE__, params)

      @impl Chime.Notifier
      def actor(_params), do: nil

      @impl Chime.Notifier
      def group(_params), do: nil

      @impl Chime.Notifier
      def workspace(_params), do: nil

      defoverridable data: 1, actor: 1, group: 1, workspace: 1

      @before_compile Chime.Notifier
    end
  end

  @doc """
  Declares a channel, with its options (see the moduledoc).
  """
  defmacro deliver(channel, opts \\ []) do
    quote bind_quoted: [channel: channel, opts: opts] do
      @chime_deliveries Chime.Notifier.__delivery__(__MODULE__, channel, opts)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    deliveries = env.module |> Module.get_attribute(:chime_deliveries) |> Enum.reverse()
    config = Module.get_attribute(env.module, :chime_config)

    check(env, deliveries)

    quote do
      @doc false
      def __chime__(:deliveries), do: unquote(Macro.escape(deliveries))
      def __chime__(:category), do: unquote(config.category)
      def __chime__(:kind), do: unquote(config.kind)
      def __chime__(:required), do: unquote(config.required)
      def __chime__(:notify_actor), do: unquote(config.notify_actor)
      def __chime__(:group_window), do: unquote(config.group_window)
    end
  end

  # The checks of a notifier's declarations, when it compiles.
  defp check(env, deliveries) do
    channels = Enum.map(deliveries, & &1.channel)

    if deliveries == [] do
      IO.warn(
        "#{inspect(env.module)} declares no channel: add deliver :feed, deliver :email, ...",
        Macro.Env.stacktrace(env)
      )
    end

    case channels -- Enum.uniq(channels) do
      [] ->
        :ok

      [twice | _] ->
        raise ArgumentError, "#{inspect(env.module)} declares the channel #{inspect(twice)} twice"
    end

    for {channel, fun, arity} <- [{"feed", :feed, 2}, {"email", :email, 3}],
        channel in channels,
        not Module.defines?(env.module, {fun, arity}) do
      IO.warn(
        "#{inspect(env.module)} delivers by #{channel} but defines no #{fun}/#{arity}",
        Macro.Env.stacktrace(env)
      )
    end

    for delivery <- deliveries,
        name <- delivery.if ++ delivery.unless,
        is_atom(name) and name not in [:read, :seen],
        not Module.defines?(env.module, {name, 2}) do
      raise ArgumentError,
            "#{inspect(env.module)} delivers by #{delivery.channel} with a condition " <>
              "#{inspect(name)}, but defines no #{name}/2"
    end
  end

  @doc false
  def __config__(module, opts) do
    category =
      case Keyword.fetch(opts, :category) do
        {:ok, category} when is_atom(category) and not is_nil(category) ->
          Atom.to_string(category)

        {:ok, category} when is_binary(category) ->
          category

        _ ->
          raise ArgumentError,
                "#{inspect(module)} needs a :category: use Chime.Notifier, category: :comments"
      end

    kind =
      Keyword.get_lazy(opts, :kind, fn ->
        module |> Module.split() |> List.last() |> Macro.underscore()
      end)

    %{
      category: category,
      kind: to_string(kind),
      required: Keyword.get(opts, :required, false) == true,
      notify_actor: Keyword.get(opts, :notify_actor, false) == true,
      group_window: seconds(module, :group_window, Keyword.get(opts, :group_window, {1, :hour}))
    }
  end

  @doc false
  def __delivery__(module, channel, opts) when is_atom(channel) and is_list(opts) do
    case Keyword.split(opts, [:wait, :if, :unless]) do
      {_opts, []} ->
        :ok

      {_opts, other} ->
        raise ArgumentError,
              "deliver takes :wait, :if and :unless, got: #{inspect(Keyword.keys(other))}"
    end

    if channel == :feed and opts[:wait] do
      raise ArgumentError, "#{inspect(module)}: the feed goes at once, with no :wait"
    end

    if channel == :feed and Enum.any?(List.wrap(opts[:unless]), &(&1 in [:read, :seen])) do
      raise ArgumentError,
            "#{inspect(module)}: the feed is decided when the notification comes, " <>
              "before it can be read or seen"
    end

    %{
      channel: Atom.to_string(channel),
      wait: seconds(module, :wait, Keyword.get(opts, :wait, 0)),
      if: conditions(module, :if, opts[:if]),
      unless: conditions(module, :unless, opts[:unless])
    }
  end

  def __delivery__(module, channel, _opts) do
    raise ArgumentError,
          "#{inspect(module)}: deliver takes the name of a channel (:feed, :email, ...), got: #{inspect(channel)}"
  end

  defp seconds(_module, _key, seconds) when is_integer(seconds) and seconds >= 0, do: seconds

  defp seconds(_module, _key, {n, unit})
       when is_integer(n) and n >= 0 and is_map_key(@units, unit),
       do: n * Map.fetch!(@units, unit)

  defp seconds(module, key, other) do
    raise ArgumentError,
          "#{inspect(module)}: #{inspect(key)} must be {n, :second | :minute | :hour | :day} " <>
            "or a number of seconds, got: #{inspect(other)}"
  end

  defp conditions(_module, _key, nil), do: []

  defp conditions(module, key, list) when is_list(list),
    do: Enum.flat_map(list, &conditions(module, key, &1))

  defp conditions(module, :if, name) when name in [:read, :seen] do
    raise ArgumentError,
          "#{inspect(module)}: #{inspect(name)} is a condition of :unless (unless: #{inspect(name)})"
  end

  defp conditions(_module, _key, name) when is_atom(name), do: [name]

  defp conditions(_module, _key, {mod, fun}) when is_atom(mod) and is_atom(fun),
    do: [{mod, fun}]

  defp conditions(module, key, other) do
    raise ArgumentError,
          "#{inspect(module)}: #{inspect(key)} must be the name of a function of the notifier " <>
            "or {module, function}, got: #{inspect(other)}"
  end

  @doc false
  # The params as JSON: what the default data/1 keeps.
  @spec json!(module(), term()) :: map()
  def json!(module, params) do
    case params |> JSON.encode!() |> JSON.decode!() do
      map when is_map(map) -> map
      _other -> raise ArgumentError, "#{inspect(module)}.data/1 must return a map"
    end
  rescue
    error in [Protocol.UndefinedError] ->
      reraise ArgumentError,
              "#{inspect(module)} keeps its params as JSON, and they are not " <>
                "(#{Exception.message(error)}): write data/1 to keep what the feed and the " <>
                "emails need",
              __STACKTRACE__
  end

  @doc false
  # Whether a module is a notifier.
  @spec notifier?(module()) :: boolean()
  def notifier?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__chime__, 1)
  end
end
