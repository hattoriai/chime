defmodule Chime.API do
  @moduledoc ~S"""
  The feed and the preferences as JSON, for a frontend that Phoenix does
  not render: React, Vue, Svelte, a mobile app. Mounted with
  `Chime.Router.chime_api/2`:

      scope "/api" do
        pipe_through :api_authenticated
        chime_api "/notifications"
      end

  Mount it behind the app's own API pipeline, the one that knows who is
  signed in (a session, a bearer token of the app's): the resolver reads
  the person from the conn (`c:Chime.Resolver.resolve_recipient/1`). A
  request with no person is a 401. A request may instead carry a token of
  `Chime.Token`, as `Bearer <token>` or `?token=`: for an `EventSource`,
  which cannot send headers, and pages on another origin.

  ## The routes

    * `GET /` - the person's feed, the latest first:
      `{"notifications": [...], "more": bool, "unseen": n, "unread": n}`.
      `?before=<id>` the page after a notification; `?limit=` up to 100
      (20); `?filter=` `inbox` (not archived, the default), `unread`,
      `archived` or `all`.
    * `GET /counts` - `{"unseen": n, "unread": n}`: one row, cheap enough
      to ask often.
    * `POST /seen` - the feed seen: the dot goes. The counts.
    * `POST /read` - every notification read. The counts.
    * `POST /:id/read`, `/:id/unread`, `/:id/archive`, `/:id/unarchive` -
      one notification. The counts; a 404 for one the person does not
      have.
    * `GET /preferences` - the person's settings:
      `{"categories": [{"key", "label", "description", "required",
      "settings": {"feed": "on", "email": "daily"}}], "channels": [{"key":
      "email", "settings": ["on", "daily", "weekly", "off"]}]}`.
    * `PUT /preferences` - changes settings, with
      `{"preferences": {"comments": {"email": "daily"}}}` as the body:
      the settings as `GET` gives them, or a 422 with
      `{"error": code, "category", "channel"}` (`"required"`,
      `"unknown_category"`, `"unknown_channel"`, `"invalid_setting"`) and
      nothing changed.
    * `GET /stream` - the person's live news, as server-sent events
      (`text/event-stream`): `counts` at once, then `notified` when a
      notification comes and `updated` when they see or read in another
      tab, each with `{"unseen": n, "unread": n}` as its data, and a
      comment every 25 seconds to keep the connection.
    * `POST /token` - a token of `Chime.Token` for the person of the
      request: `{"token": "...", "expiresIn": seconds}`.

  A notification is:

      {
        "id": "0193…",
        "kind": "new_comment",
        "category": "comments",
        "title": "Ana and 2 others commented on Tokyo",
        "body": "Lovely light.",
        "url": "/stories/42",
        "icon": "comment",
        "extra": {},
        "count": 3,
        "actors": [{"id": "user:7", "name": "Ana"}],
        "seen": true, "read": false, "archived": false,
        "seenAt": "2026-10-25T14:03:00Z", "readAt": null, "archivedAt": null,
        "insertedAt": "2026-10-25T14:02:11Z", "updatedAt": "2026-10-25T14:09:40Z"
      }

  `title`, `body`, `url` and `icon` are the notifier's `feed/2`, rendered
  for the request (its language, through the app's own plugs); `extra`
  has whatever else it gave.

  An error is `{"error": code}`: `"unauthorized"` (a 401, with
  `"token_expired"` for a token past its time), `"not_found"`.

  Behind the app's `protect_from_forgery`, a `POST` needs the CSRF token
  of the session in the `x-csrf-token` header.
  """

  @behaviour Plug

  import Plug.Conn

  alias Chime.{Config, Counts, Feed, Notification, Preferences, Resolver, Token}

  @limit 20
  @ping 25_000

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, action) do
    config = Config.get()
    conn = fetch_query_params(conn)

    case reader(conn, config) do
      {:ok, recipient} -> handle(action, conn, config, recipient)
      {:error, :expired} -> json(conn, 401, %{error: "token_expired"})
      {:error, _} -> json(conn, 401, %{error: "unauthorized"})
    end
  end

  # The person of a token of Chime's when the request has one, else the
  # resolver's (the bearer may be the app's own token).
  defp reader(conn, config) do
    token = bearer(conn) || conn.query_params["token"]
    max_age = conn.assigns.mount.options[:token_max_age] || 86_400

    case token && Token.verify(token, max_age: max_age) do
      {:ok, id} -> {:ok, id}
      {:error, :expired} -> {:error, :expired}
      _ -> resolve(conn, config)
    end
  end

  defp resolve(conn, config) do
    case Resolver.reader(config.resolver, conn) do
      nil -> {:error, :unauthorized}
      id -> {:ok, id}
    end
  end

  defp bearer(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> String.trim(token)
      _ -> nil
    end
  end

  defp handle(:index, conn, config, recipient) do
    params = conn.query_params
    limit = params |> Map.get("limit", "#{@limit}") |> parse_int(@limit) |> min(100) |> max(1)

    filter =
      case params["filter"] do
        f when f in ["unread", "archived", "all"] -> String.to_existing_atom(f)
        _ -> :inbox
      end

    notifications =
      Feed.list(config, recipient, limit: limit + 1, filter: filter, before: params["before"])

    json(
      conn,
      200,
      Map.merge(Counts.get(config, recipient), %{
        notifications: notifications |> Enum.take(limit) |> Enum.map(&Feed.json/1),
        more: length(notifications) > limit
      })
    )
  end

  defp handle(:counts, conn, config, recipient),
    do: json(conn, 200, Counts.get(config, recipient))

  defp handle(:seen, conn, config, recipient),
    do: json(conn, 200, Feed.mark(config, recipient, :seen, :all))

  defp handle(:read_all, conn, config, recipient),
    do: json(conn, 200, Feed.mark(config, recipient, :read, :all))

  defp handle(action, conn, config, recipient)
       when action in [:read, :unread, :archive, :unarchive] do
    id = conn.path_params["id"]

    with {:ok, id} <- Ecto.UUID.cast(id),
         %Notification{} <-
           config.repo.get_by(Notification, [id: id, recipient: recipient], prefix: config.prefix) do
      json(conn, 200, Feed.mark(config, recipient, action, [id]))
    else
      _ -> json(conn, 404, %{error: "not_found"})
    end
  end

  defp handle(:preferences, conn, config, recipient),
    do: json(conn, 200, preferences_json(config, recipient))

  defp handle(:put_preferences, conn, config, recipient) do
    {body, conn} = body(conn)

    changes =
      for {category, settings} when is_map(settings) <- Map.get(body, "preferences") || %{},
          {channel, setting} <- settings,
          do: {to_string(category), to_string(channel), to_string(setting)}

    result =
      config.repo.transaction(fn ->
        Enum.each(changes, &put_preference(config, recipient, &1))
      end)

    case result do
      {:ok, _} ->
        json(conn, 200, preferences_json(config, recipient))

      {:error, {code, category, channel}} ->
        json(conn, 422, %{error: Atom.to_string(code), category: category, channel: channel})
    end
  end

  defp handle(:token, conn, _config, recipient) do
    max_age = conn.assigns.mount.options[:token_max_age] || 86_400
    json(conn, 200, %{token: Token.sign(recipient), expiresIn: max_age})
  end

  defp handle(:stream, conn, config, recipient) do
    Phoenix.PubSub.subscribe(config.pubsub, Chime.topic(recipient))

    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    case event(conn, "counts", Counts.get(config, recipient)) do
      {:ok, conn} -> stream(conn)
      {:error, _closed} -> conn
    end
  end

  # The person's news, until the connection closes.
  defp stream(conn) do
    receive do
      {Chime, kind, counts} when kind in [:notified, :updated] ->
        continue(conn, event(conn, Atom.to_string(kind), counts))

      {__MODULE__, :close} ->
        conn
    after
      @ping -> continue(conn, chunk(conn, ": ping\n\n"))
    end
  end

  defp continue(_conn, {:ok, conn}), do: stream(conn)
  defp continue(conn, {:error, _closed}), do: conn

  defp event(conn, name, data), do: chunk(conn, "event: #{name}\ndata: #{JSON.encode!(data)}\n\n")

  # A change of the preferences, or the transaction's rollback.
  defp put_preference(config, recipient, {category, channel, setting}) do
    case Preferences.put(config, recipient, category, channel, setting) do
      :ok -> :ok
      {:error, code} -> config.repo.rollback({code, category, channel})
    end
  end

  defp preferences_json(config, recipient) do
    %{
      categories:
        Enum.map(Preferences.for_recipient(config, recipient), fn %{category: c, settings: s} ->
          %{
            key: c.key,
            label: c.label,
            description: c.description,
            required: c.required,
            settings: s
          }
        end),
      channels:
        Enum.map(Config.channel_names(config), fn channel ->
          %{
            key: channel,
            settings: if(channel == "email", do: ~w(on daily weekly off), else: ~w(on off))
          }
        end)
    }
  end

  # The body as JSON: the app's parsers' when they read it, else read here.
  defp body(%Plug.Conn{body_params: %Plug.Conn.Unfetched{}} = conn) do
    case read_body(conn) do
      {:ok, "", conn} -> {%{}, conn}
      {:ok, body, conn} -> {decode(body), conn}
      _ -> {%{}, conn}
    end
  end

  defp body(conn), do: {conn.body_params, conn}

  defp decode(body) do
    case JSON.decode(body) do
      {:ok, map} when is_map(map) -> map
      _ -> %{}
    end
  end

  defp parse_int(string, default) do
    case Integer.parse(string) do
      {n, ""} -> n
      _ -> default
    end
  end

  defp json(conn, status, data) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, JSON.encode!(data))
  end
end
