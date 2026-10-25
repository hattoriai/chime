# The Chime development server: `mix dev`, then http://localhost:4100.
#
# One Phoenix endpoint with a small app ("Atelier", a photographers'
# stories), its people and notifications in SQLite (tmp/dev.sqlite3),
# made again at each start:
#
#   * /                        - the app, with the bell, as Ana (?as=user:2 for Rui);
#   * /settings                - Ana's preferences;
#   * /admin/notifications     - Chime's admin, and its previews;
#   * /api/notifications       - the JSON API, as Ana.
#
# The deliveries are Oban jobs, run by the server: an email goes to
# Swoosh's local mailbox.

port = "PORT" |> System.get_env("4100") |> String.to_integer()
database = Path.expand("tmp/dev.sqlite3", __DIR__)
File.mkdir_p!(Path.dirname(database))
for file <- Path.wildcard(database <> "*"), do: File.rm!(file)

Application.put_env(:phoenix, :json_library, JSON)
Logger.configure(level: :info)

Application.put_env(:chime, ChimeDev.Repo, database: database, pool_size: 5)
Application.put_env(:chime, ChimeDev.Mailer, adapter: Swoosh.Adapters.Local)
Application.put_env(:swoosh, :local, true)

Application.put_env(:chime, ChimeDev.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  check_origin: false,
  debug_errors: true,
  http: [ip: {127, 0, 0, 1}, port: port],
  live_view: [signing_salt: "chime-dev-live-view-salt"],
  pubsub_server: ChimeDev.PubSub,
  secret_key_base: String.duplicate("chime-development-secret-", 3),
  server: true,
  url: [host: "localhost", port: port]
)

defmodule ChimeDev.Repo do
  use Ecto.Repo, otp_app: :chime, adapter: Ecto.Adapters.SQLite3
end

defmodule ChimeDev.Mailer do
  use Swoosh.Mailer, otp_app: :chime
end

defmodule ChimeDev.Migration do
  use Ecto.Migration

  def up do
    Oban.Migration.up()
    Chime.Migrations.up(version: 1)
  end
end

defmodule ChimeDev.People do
  @people %{
    "user:1" => %Chime.Recipient{
      id: "user:1",
      name: "Ana Sousa",
      email: "ana@atelier.test",
      time_zone: "Etc/UTC"
    },
    "user:2" => %Chime.Recipient{id: "user:2", name: "Rui Costa", email: "rui@atelier.test"},
    "user:3" => %Chime.Recipient{id: "user:3", name: "Kenji Mori", email: nil}
  }

  def all, do: @people
end

defmodule ChimeDev.Resolver do
  @behaviour Chime.Resolver

  @impl true
  def recipients(ids), do: ChimeDev.People.all() |> Map.take(ids) |> Map.values()

  @impl true
  def resolve_recipient(%Plug.Conn{} = conn), do: Plug.Conn.get_session(conn, "as") || "user:1"
  def resolve_recipient(%{assigns: assigns}), do: assigns[:current_user]
end

defmodule ChimeDev.AdminAccess do
  @behaviour Chime.Admin.Access
  @impl true
  def allow?(_conn), do: true
end

defmodule ChimeDev.NewComment do
  use Chime.Notifier, category: :comments, group_window: {1, :hour}

  deliver :feed
  deliver :email, wait: {10, :minute}, unless: :read

  @impl true
  def data(%{story: story, text: text}), do: %{"story" => story, "text" => text}

  @impl true
  def actor(%{author: author}), do: author

  @impl true
  def group(%{story: story}), do: "story:#{story}"

  @impl true
  def feed(data, notification) do
    %{
      title: "#{Chime.actors(notification)} commented on #{data["story"]}",
      body: data["text"],
      url: "/stories"
    }
  end

  @impl true
  def email(data, _recipient, notification) do
    Swoosh.Email.new(
      subject: "#{Chime.actors(notification)} commented on #{data["story"]}",
      html_body: """
      <div style="font-family: system-ui; max-width: 32rem">
        <h2 style="font-weight: 600">#{Chime.actors(notification)} commented on <em>#{data["story"]}</em></h2>
        <blockquote style="border-left: 3px solid #ea580c; margin: 0; padding-left: 1rem; color: #444">#{data["text"]}</blockquote>
        <p><a href="#" style="background: #1c1917; color: #fff; padding: .5rem 1rem; border-radius: .4rem; text-decoration: none">Read the story</a></p>
      </div>
      """,
      text_body: data["text"]
    )
  end

  @impl true
  def preview do
    [
      {"A comment",
       %{
         story: "Tokyo at night",
         text: "The light on the wet street is perfect.",
         author: %{"id" => "user:2", "name" => "Rui"}
       }},
      {"A long comment",
       %{
         story: "Kyoto, early",
         text: String.duplicate("I keep coming back to this one. ", 6),
         author: %{"id" => "user:3", "name" => "Kenji"}
       }}
    ]
  end
end

defmodule ChimeDev.Invited do
  use Chime.Notifier, category: :collectives

  deliver :feed
  deliver :email

  @impl true
  def data(%{collective: collective, by: by}), do: %{"collective" => collective, "by" => by}

  @impl true
  def feed(data, %{action: nil}) do
    %{
      title: "#{data["by"]} invited you to #{data["collective"]}",
      body: "A collective of street photographers.",
      url: "/collectives",
      actions: [%{key: "accept", label: "Accept"}, %{key: "decline", label: "Decline"}]
    }
  end

  def feed(data, %{action: action}),
    do: %{title: "You #{action}ed #{data["collective"]}", url: "/collectives"}

  @impl true
  def act(_action, _data, _notification), do: :ok

  @impl true
  def email(data, _recipient, _notification),
    do:
      Swoosh.Email.new(
        subject: "Join #{data["collective"]}",
        text_body: "#{data["by"]} invited you."
      )

  @impl true
  def preview, do: %{collective: "Night Walkers", by: "Mei"}
end

defmodule ChimeDev.PaymentFailed do
  use Chime.Notifier, category: :billing

  deliver :feed
  deliver :email

  @impl true
  def feed(data, _notification),
    do: %{
      title: "Your payment of #{data["amount"]} failed",
      body: "Update your card to keep your plan.",
      url: "/billing"
    }

  @impl true
  def email(data, _recipient, _notification),
    do: Swoosh.Email.new(subject: "Your payment failed", text_body: "Of #{data["amount"]}.")

  @impl true
  def preview, do: %{"amount" => "€12"}
end

defmodule ChimeDev.Layout do
  use Phoenix.Component

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Atelier</title>
        <style><%= Phoenix.HTML.raw(File.read!("priv/static/chime.css")) %></style>
        <style>
          body { font: 15px/1.5 system-ui, sans-serif; margin: 0; color: #1c1917; background: #fafaf9; }
          .top { display: flex; justify-content: space-between; align-items: center; padding: .75rem 1.5rem; background: #fff; border-bottom: 1px solid #e7e5e4; }
          .top b { font-size: 1.1rem; }
          .who { display: flex; gap: 1rem; align-items: center; position: relative; }
          .who .chime-feed { right: 0; top: 2.5rem; }
          main { padding: 2rem 1.5rem; max-width: 48rem; }
        </style>
        <script src="/js/phoenix/phoenix.min.js"></script>
        <script src="/js/live_view/phoenix_live_view.min.js"></script>
        <script>
          window.addEventListener("DOMContentLoaded", () => {
            const csrf = document.querySelector("meta[name='csrf-token']").content
            new LiveView.LiveSocket("/live", Phoenix.Socket, {params: {_csrf_token: csrf}}).connect()
          })
        </script>
      </head>
      <body>{@inner_content}</body>
    </html>
    """
  end
end

defmodule ChimeDev.AppLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <header class="top">
      <b>Atelier</b>
      <div class="who">
        <span>{@current_user}</span>
        <Chime.Components.bell chime={@chime} />
        <Chime.Components.feed chime={@chime} />
      </div>
    </header>
    <main>
      <h1 :if={@live_action == :index}>Your stories</h1>
      <Chime.Components.preferences :if={@live_action == :settings} id="prefs" chime={@chime} />
    </main>
    """
  end
end

defmodule ChimeDev.AssignUser do
  def on_mount(:default, _params, session, socket),
    do: {:cont, Phoenix.Component.assign(socket, :current_user, session["as"] || "user:1")}
end

defmodule ChimeDev.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router
  import Chime.Router

  pipeline :browser do
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :as
    plug :put_root_layout, html: {ChimeDev.Layout, :root}
    plug :protect_from_forgery
  end

  defp as(conn, _opts) do
    case conn.params["as"] do
      nil -> conn
      as -> Plug.Conn.put_session(conn, "as", as)
    end
  end

  scope "/" do
    pipe_through :browser

    chime_admin("/admin/notifications", access: ChimeDev.AdminAccess)
    chime_api "/api/notifications"
    chime_mail("/notifications/mail", app_name: "Atelier")

    live_session :app, on_mount: [ChimeDev.AssignUser, Chime.Live] do
      live "/", ChimeDev.AppLive, :index
      live "/settings", ChimeDev.AppLive, :settings
    end
  end
end

defmodule ChimeDev.Endpoint do
  use Phoenix.Endpoint, otp_app: :chime

  @session [store: :cookie, key: "_chime_dev", signing_salt: "chime-dev"]
  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session]]

  plug Plug.Static, at: "/js/phoenix", from: {:phoenix, "priv/static"}
  plug Plug.Static, at: "/js/live_view", from: {:phoenix_live_view, "priv/static"}
  plug Plug.Parsers, parsers: [:urlencoded, :json], json_decoder: JSON
  plug Plug.Session, @session
  plug ChimeDev.Router
end

{:ok, _} =
  Application.ensure_all_started([:phoenix, :phoenix_live_view, :bandit, :ecto_sqlite3, :oban])

{:ok, _} = Phoenix.PubSub.Supervisor.start_link(name: ChimeDev.PubSub)
{:ok, _} = ChimeDev.Repo.start_link()
Ecto.Migrator.run(ChimeDev.Repo, [{1, ChimeDev.Migration}], :up, all: true, log: false)
{:ok, _} = Oban.start_link(repo: ChimeDev.Repo, engine: Oban.Engines.Lite, queues: [default: 10])

{:ok, _} =
  Chime.start_link(
    repo: ChimeDev.Repo,
    pubsub: ChimeDev.PubSub,
    resolver: ChimeDev.Resolver,
    mailer: ChimeDev.Mailer,
    email_from: {"Atelier", "hello@atelier.test"},
    secret_key_base: String.duplicate("chime-development-secret-", 3),
    mail_url: "http://localhost:#{port}/notifications/mail",
    url: "http://localhost:#{port}",
    categories: [
      comments: [label: "Comments on your stories", description: "When someone comments"],
      collectives: [label: "Collectives", defaults: [email: :daily]],
      billing: [label: "Billing", required: true]
    ]
  )

# The notifications of the app, a few hours of them.
now = DateTime.utc_now()
ago = fn minutes -> DateTime.add(now, -minutes * 60) end

Chime.notify(ChimeDev.PaymentFailed, %{"amount" => "€12"}, to: "user:1", now: ago.(300))

Chime.notify(ChimeDev.Invited, %{collective: "Night Walkers", by: "Mei"},
  to: ["user:1", "user:3"],
  now: ago.(120)
)

for {author, minutes} <- [{"Rui", 50}, {"Kenji", 30}, {"Mei", 8}] do
  Chime.notify(
    ChimeDev.NewComment,
    %{
      story: "Tokyo at night",
      text: "The light here is perfect.",
      author: %{"id" => author, "name" => author}
    },
    to: ["user:1", "user:3"],
    now: ago.(minutes)
  )
end

Chime.notify(
  ChimeDev.NewComment,
  %{
    story: "Kyoto, early",
    text: "What lens is this?",
    author: %{"id" => "user:2", "name" => "Rui"}
  },
  to: "user:1",
  now: ago.(3)
)

Chime.put_preference("user:3", :comments, :email, :off)

{:ok, _} = Supervisor.start_link([ChimeDev.Endpoint], strategy: :one_for_one)
IO.puts("Chime's development server: http://localhost:#{port}")
Process.sleep(:infinity)
