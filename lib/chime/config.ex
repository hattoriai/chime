defmodule Chime.Config do
  @moduledoc """
  The options of Chime, given to its child in the app's supervision tree,
  after the repo, the PubSub and Oban:

      children = [
        MyApp.Repo,
        {Phoenix.PubSub, name: MyApp.PubSub},
        {Oban, Application.fetch_env!(:my_app, Oban)},
        {Chime,
         repo: MyApp.Repo,
         pubsub: MyApp.PubSub,
         resolver: MyApp.ChimeResolver,
         mailer: MyApp.Mailer,
         email_from: {"Atelier", "hello@atelier.app"},
         secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
         mail_url: "https://atelier.app/notifications/mail",
         categories: [
           comments: [label: "Comments on your stories"],
           followers: [label: "New followers", defaults: [email: :weekly]],
           billing: [label: "Billing", required: true]
         ]},
        MyAppWeb.Endpoint
      ]

  Options:

    * `:repo` - the app's Ecto repo, where the notifications are
      (required).
    * `:pubsub` - the app's `Phoenix.PubSub`, on which the app's pages
      hear of a notification as it comes (required).
    * `:resolver` - the app's `Chime.Resolver`: who the people of the app
      are, by id, and who reads the feed of a request (required).
    * `:oban` - the app's Oban, which runs every delivery but the feed's:
      `Oban` (the default), or `[name: MyApp.Oban, queue: :notifications]`
      for another instance or queue (`:default`). The queue must be one
      the app runs.
    * `:prefix` - the schema of the tables, in PostgreSQL.
    * `:categories` - the kinds of notification a person can turn on and
      off, in the order the preferences show them. Each is a key with
      its options:
        * `:label` - its name in the preferences (the key, capitalized).
        * `:description` - a line under the label.
        * `:required` - a notification of the category goes whatever the
          person's preferences, and its emails have no link to
          unsubscribe: receipts, security, the account (`false`).
        * `:defaults` - the setting of each channel for a person who has
          not changed it: `[email: :daily, feed: :on]`. A channel not
          named is `:on`.

      Without it, every notifier's category is taken, with every channel
      on, and the preferences show none.
    * `:channels` - the app's own channels, by name, each a module of
      `Chime.Channel` or `{module, opts}`:
      `[telegram: MyApp.Chime.Telegram, sms: {MyApp.Chime.SMS, from: "+351..."}]`.
      `:feed` and `:email` are Chime's.
    * `:mailer` - the app's `Swoosh.Mailer`, which sends the emails of the
      `:email` channel and the digests (required with it).
    * `:email_from` - who the emails are from: `{"Atelier", "hello@atelier.app"}`
      or an address (required with `:mailer`).
    * `:secret_key_base` - the secret that signs the links to unsubscribe
      and the tokens of the JSON API (`Chime.Token`). At least 32 bytes.
    * `:mail_url` - the address where `chime_mail` is mounted, whole
      (`"https://atelier.app/notifications/mail"`), for the links of the
      emails: to unsubscribe (and the `List-Unsubscribe` headers), and to
      open a notification, which reads it (`Chime.link/2`). With
      `:secret_key_base`; without them, the emails have no such links.
    * `:digest` - when the digests go, in each person's time zone (UTC
      for a person without one):
        * `:at` - the hour (`9`, for 09:00).
        * `:weekly_on` - the day of the weekly digest (`:monday`).
        * `:email` - the app's module that writes the digest's email,
          with `email(recipient, items, period)` (see `Chime.Digest`).
          Without it, Chime's own: a list of the notifications as the
          feed shows them.
    * `:url` - the app's address (`"https://atelier.app"`), for the links
      of the digests to the notifications whose feed `:url` is a path.
    * `:gettext` - the app's Gettext backend (`MyAppWeb.Gettext`), in
      which Chime's words are translated, in the `"chime"` domain (see
      `Chime.Messages`). Without it, they are English.
    * `:limits` - the most each person gets by a channel in a time, by
      channel: `[email: {3, :hour}, sms: {5, :day}]`. One past the limit
      waits until it is under again. Required notifications do not count
      against it, and are not held by it.
    * `:quiet_hours` - the hours of the night, in each person's time zone,
      when nothing but the feed goes: `{22, 8}`, from 22:00 to 08:00. What
      comes then waits for the end. A person's own (`:quiet_hours` of
      `Chime.Recipient`) comes first. Required notifications go all the
      same (none).
    * `:push` - the push services of the `:push` channel, each with its
      keys (see the [Push](push.md) guide); the channel is there with one:
        * `:web` - Web Push, for browsers: `:public_key` and `:private_key`,
          the app's VAPID keys, URL-safe Base64 (`mix chime.gen.vapid`),
          `:subject`, a `mailto:` or `https:` address of the app's, and
          `:ttl`, how long a push waits for a browser that is off, in
          seconds (one day).
        * `:apns` - Apple's: `:key`, the `.p8` key (its text), `:key_id`,
          `:team_id`, `:topic`, the app's bundle id, and `:env`,
          `:production` or `:sandbox` (`:production`).
        * `:fcm` - Firebase's: `:service_account`, its JSON (the text, or a
          map), from Firebase's console.
        * `:req_options` - options of the requests to the services, for
          `Req` (`[]`).
    * `:keep_days` - how long a notification is kept, with its deliveries,
      after it came (`180`). `nil` keeps them for ever.
    * `:scheduler` - `false` starts nothing that runs by itself: no
      digest job, no cleanup. For an app's tests (`true`).
  """

  @weekdays ~w(monday tuesday wednesday thursday friday saturday sunday)a

  @enforce_keys [:repo, :pubsub, :resolver]
  defstruct [
    :repo,
    :pubsub,
    :resolver,
    :prefix,
    :mailer,
    :email_from,
    :secret_key_base,
    :mail_url,
    :url,
    :gettext,
    :quiet_hours,
    :push,
    limits: %{},
    oban: %{name: Oban, queue: :default},
    categories: nil,
    channels: %{},
    digest: %{at: 9, weekly_on: :monday, email: nil},
    keep_days: 180,
    scheduler: true
  ]

  @type category :: %{
          key: String.t(),
          label: String.t(),
          description: String.t() | nil,
          required: boolean(),
          defaults: %{String.t() => String.t()}
        }

  @type t :: %__MODULE__{
          repo: module(),
          pubsub: atom(),
          resolver: module(),
          prefix: String.t() | nil,
          mailer: module() | nil,
          email_from: String.t() | {String.t(), String.t()} | nil,
          secret_key_base: String.t() | nil,
          mail_url: String.t() | nil,
          url: String.t() | nil,
          gettext: module() | nil,
          quiet_hours: {0..23, 0..23} | nil,
          push: map() | nil,
          limits: %{String.t() => {pos_integer(), pos_integer()}},
          oban: %{name: term(), queue: atom()},
          categories: [category()] | nil,
          channels: %{String.t() => {module(), keyword()}},
          digest: %{at: 0..23, weekly_on: atom(), email: module() | nil},
          keep_days: pos_integer() | nil,
          scheduler: boolean()
        }

  @key {Chime, :config}

  @doc "Builds the config from the options of the child, and checks them."
  @spec new(keyword()) :: t()
  def new(opts) do
    repo = Keyword.get(opts, :repo) || raise ArgumentError, "Chime needs the :repo option"
    pubsub = Keyword.get(opts, :pubsub) || raise ArgumentError, "Chime needs the :pubsub option"

    resolver =
      Keyword.get(opts, :resolver) || raise ArgumentError, "Chime needs the :resolver option"

    check_mailer(opts)

    %__MODULE__{
      repo: repo,
      pubsub: pubsub,
      resolver: resolver,
      prefix: opts[:prefix],
      mailer: opts[:mailer],
      email_from: opts[:email_from],
      secret_key_base: secret_key_base(opts[:secret_key_base]),
      mail_url: opts[:mail_url] && String.trim_trailing(opts[:mail_url], "/"),
      url: opts[:url] && String.trim_trailing(opts[:url], "/"),
      gettext: opts[:gettext],
      quiet_hours: quiet_hours(opts[:quiet_hours]),
      limits: limits(Keyword.get(opts, :limits, [])),
      push: push(opts[:push]),
      oban: oban(Keyword.get(opts, :oban, Oban)),
      categories: categories(opts[:categories]),
      channels: channels(Keyword.get(opts, :channels, []), opts[:push]),
      digest: digest(Keyword.get(opts, :digest, [])),
      keep_days: keep_days(Keyword.get(opts, :keep_days, 180)),
      scheduler: scheduler(Keyword.get(opts, :scheduler, true))
    }
  end

  @doc false
  @spec put(t()) :: :ok
  def put(%__MODULE__{} = config), do: :persistent_term.put(@key, config)

  @doc false
  # The config of the node, as Chime's child put it.
  @spec get() :: t()
  def get do
    case :persistent_term.get(@key, nil) do
      %__MODULE__{} = config -> config
      nil -> raise "Chime is not started: add {Chime, opts} to your supervision tree"
    end
  end

  @doc false
  # The category of a key, as the config has it, or one with every channel
  # on when the config names none. A category the config does not name is
  # an error, so that a typo in a notifier does not go unseen.
  @spec category(t(), String.t()) :: category()
  def category(%__MODULE__{categories: nil}, key), do: default_category(key)

  def category(%__MODULE__{categories: categories}, key) do
    Enum.find(categories, &(&1.key == key)) ||
      raise ArgumentError,
            "the category #{inspect(key)} is not one of the :categories of Chime's config: " <>
              Enum.map_join(categories, ", ", &inspect(&1.key))
  end

  @doc false
  # The channels a person can set, in order: the feed, email when the
  # app has a mailer, then the app's own.
  @spec channel_names(t()) :: [String.t()]
  def channel_names(%__MODULE__{} = config) do
    ["feed"] ++ if(config.mailer, do: ["email"], else: []) ++ Map.keys(config.channels)
  end

  @doc false
  # The module and options of a channel by name.
  @spec channel(t(), String.t()) :: {module(), keyword()}
  def channel(%__MODULE__{}, "email"), do: {Chime.Channels.Email, []}

  def channel(%__MODULE__{channels: channels}, name) do
    Map.get(channels, name) ||
      raise ArgumentError,
            "the channel #{inspect(name)} is not one of Chime's (:feed, :email) or the " <>
              ":channels of its config"
  end

  defp default_category(key) do
    %{key: key, label: label(key), description: nil, required: false, defaults: %{}}
  end

  defp label(key), do: key |> String.replace("_", " ") |> String.capitalize()

  defp check_mailer(opts) do
    if opts[:mailer] do
      unless Code.ensure_loaded?(Swoosh.Email) do
        raise ArgumentError, "the :mailer option needs the :swoosh dependency"
      end

      if opts[:email_from] == nil do
        raise ArgumentError, "the :mailer option needs :email_from, who the emails are from"
      end
    end
  end

  defp secret_key_base(secret) do
    if secret != nil and (not is_binary(secret) or byte_size(secret) < 32) do
      raise ArgumentError, ":secret_key_base must be a string of at least 32 bytes"
    end

    secret
  end

  defp oban(name) when is_atom(name), do: %{name: name, queue: :default}

  defp oban(opts) when is_list(opts) do
    %{name: Keyword.get(opts, :name, Oban), queue: Keyword.get(opts, :queue, :default)}
  end

  defp oban(other) do
    raise ArgumentError,
          ":oban must be the name of the app's Oban, or [name: ..., queue: ...], got: #{inspect(other)}"
  end

  @settings ~w(on off daily weekly)a

  defp categories(nil), do: nil

  defp categories(categories) when is_list(categories) and categories != [] do
    Enum.map(categories, fn
      {key, opts} when is_atom(key) and is_list(opts) ->
        category_spec(Atom.to_string(key), opts)

      other ->
        raise ArgumentError,
              "each of :categories is a key and its options (comments: [label: \"Comments\"]), " <>
                "got: #{inspect(other)}"
    end)
  end

  defp categories(other) do
    raise ArgumentError, ":categories must be a keyword list, got: #{inspect(other)}"
  end

  defp category_spec(key, opts) do
    defaults = Keyword.get(opts, :defaults, [])

    unless Keyword.keyword?(defaults) and Enum.all?(defaults, fn {_, s} -> s in @settings end) do
      raise ArgumentError,
            ":defaults of the category #{inspect(key)} must be a keyword list of a channel " <>
              "and :on, :off, :daily or :weekly, got: #{inspect(defaults)}"
    end

    %{
      key: key,
      label: Keyword.get(opts, :label, label(key)),
      description: opts[:description],
      required: Keyword.get(opts, :required, false) == true,
      defaults:
        Map.new(defaults, fn {channel, s} -> {Atom.to_string(channel), Atom.to_string(s)} end)
    }
  end

  defp channels(channels, push) when is_list(channels) do
    # The :push channel, with the services of :push.
    builtin = if push, do: %{"push" => {Chime.Channels.Push, []}}, else: %{}

    channels
    |> Map.new(fn
      {name, _} when name in [:feed, :email] or (name == :push and push != nil) ->
        raise ArgumentError, "#{inspect(name)} is Chime's own channel: give yours another name"

      {name, module} when is_atom(name) and is_atom(module) ->
        {Atom.to_string(name), channel_module({module, []})}

      {name, {module, opts}} when is_atom(name) and is_atom(module) and is_list(opts) ->
        {Atom.to_string(name), channel_module({module, opts})}

      other ->
        raise ArgumentError,
              "each of :channels is a name and a module of Chime.Channel, got: #{inspect(other)}"
    end)
    |> Map.merge(builtin)
  end

  defp channels(other, _push) do
    raise ArgumentError, ":channels must be a keyword list, got: #{inspect(other)}"
  end

  defp channel_module({module, opts}) do
    unless Code.ensure_loaded?(module) and function_exported?(module, :deliver, 2) do
      raise ArgumentError, "#{inspect(module)} is not a Chime.Channel: it has no deliver/2"
    end

    {module, opts}
  end

  defp digest(opts) when is_list(opts) do
    at = Keyword.get(opts, :at, 9)
    weekly_on = Keyword.get(opts, :weekly_on, :monday)

    unless at in 0..23 do
      raise ArgumentError, ":at of :digest must be an hour, 0 to 23, got: #{inspect(at)}"
    end

    unless weekly_on in @weekdays do
      raise ArgumentError,
            ":weekly_on of :digest must be a day, :monday to :sunday, got: #{inspect(weekly_on)}"
    end

    email = opts[:email]

    if email != nil and not (Code.ensure_loaded?(email) and function_exported?(email, :email, 3)) do
      raise ArgumentError,
            ":email of :digest must be a module with email/3, got: #{inspect(email)}"
    end

    %{at: at, weekly_on: weekly_on, email: email}
  end

  defp digest(other),
    do: raise(ArgumentError, ":digest must be a keyword list, got: #{inspect(other)}")

  @doc false
  def quiet_hours(nil), do: nil
  def quiet_hours(false), do: false
  def quiet_hours({from, to}) when from in 0..23 and to in 0..23 and from != to, do: {from, to}

  def quiet_hours(other) do
    raise ArgumentError,
          ":quiet_hours must be {from, to}, two hours from 0 to 23 (or nil), got: #{inspect(other)}"
  end

  @units %{second: 1, minute: 60, hour: 3600, day: 86_400}

  defp push(nil), do: nil

  defp push(opts) when is_list(opts) do
    req = Keyword.get(opts, :req_options, [])

    unless Code.ensure_loaded?(Req),
      do: raise(ArgumentError, "the :push option needs the :req dependency")

    services =
      for {service, settings} <- Keyword.take(opts, [:web, :apns, :fcm]), into: %{} do
        {service, push_service(service, settings, req)}
      end

    if services == %{}, do: raise(ArgumentError, ":push needs :web, :apns or :fcm")
    services
  end

  defp push(other),
    do: raise(ArgumentError, ":push must be a keyword list, got: #{inspect(other)}")

  defp push_service(:web, opts, req) do
    private = decode_key!(:private_key, opts[:private_key], 32)
    public = decode_key!(:public_key, opts[:public_key], 65)
    subject = opts[:subject]

    unless is_binary(subject) and String.starts_with?(subject, ["mailto:", "https:"]) do
      raise ArgumentError,
            ":subject of :web of :push must be a mailto: or https: address of the app's"
    end

    %{
      private_key: private,
      public_key: Base.url_encode64(public, padding: false),
      subject: subject,
      ttl: Keyword.get(opts, :ttl, 86_400),
      req_options: req
    }
  end

  defp push_service(:apns, opts, req) do
    for key <- [:key, :key_id, :team_id, :topic], !is_binary(opts[key]) do
      raise ArgumentError, ":apns of :push needs #{inspect(key)}"
    end

    env = Keyword.get(opts, :env, :production)

    unless env in [:production, :sandbox],
      do: raise(ArgumentError, ":env of :apns must be :production or :sandbox")

    %{
      key: opts[:key],
      key_id: opts[:key_id],
      team_id: opts[:team_id],
      topic: opts[:topic],
      env: env,
      req_options: req
    }
  end

  defp push_service(:fcm, opts, req) do
    account =
      case opts[:service_account] do
        json when is_binary(json) -> JSON.decode!(json)
        %{} = map -> Map.new(map, fn {k, v} -> {to_string(k), v} end)
        _ -> raise ArgumentError, ":fcm of :push needs :service_account, its JSON"
      end

    for key <- ["project_id", "client_email", "private_key"], !is_binary(account[key]) do
      raise ArgumentError, "the :service_account of :fcm has no #{key}"
    end

    %{
      project_id: account["project_id"],
      client_email: account["client_email"],
      private_key: account["private_key"],
      token_uri: account["token_uri"] || "https://oauth2.googleapis.com/token",
      req_options: req
    }
  end

  defp decode_key!(name, text, size) do
    case is_binary(text) && Base.url_decode64(text, padding: false) do
      {:ok, <<_::binary-size(^size)>> = key} ->
        key

      _ ->
        raise ArgumentError,
              "#{inspect(name)} of :web of :push must be a VAPID key, URL-safe Base64"
    end
  end

  defp limits(limits) when is_list(limits) do
    Map.new(limits, fn
      {channel, {n, unit}}
      when is_atom(channel) and is_integer(n) and n > 0 and is_map_key(@units, unit) ->
        {Atom.to_string(channel), {n, Map.fetch!(@units, unit)}}

      other ->
        raise ArgumentError,
              "each of :limits is a channel and {n, :minute | :hour | :day}, got: #{inspect(other)}"
    end)
  end

  defp limits(other),
    do: raise(ArgumentError, ":limits must be a keyword list, got: #{inspect(other)}")

  defp keep_days(nil), do: nil
  defp keep_days(days) when is_integer(days) and days > 0, do: days

  defp keep_days(other),
    do: raise(ArgumentError, ":keep_days must be a number of days or nil, got: #{inspect(other)}")

  defp scheduler(scheduler) when is_boolean(scheduler), do: scheduler

  defp scheduler(other),
    do: raise(ArgumentError, ":scheduler must be true or false, got: #{inspect(other)}")
end
