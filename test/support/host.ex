defmodule ChimeTest.AssignReader do
  @moduledoc "The app's own on_mount: the person of the session, in the assigns."
  def on_mount(:default, _params, session, socket) do
    if locale = session["locale"], do: Gettext.put_locale(ChimeTest.Gettext, locale)
    socket = Phoenix.Component.assign(socket, :current_workspace, session["workspace"])
    {:cont, Phoenix.Component.assign(socket, :current_reader, session["reader"])}
  end
end

defmodule ChimeTest.BellLive do
  @moduledoc "A page of the app, with the bell, the feed and the preferences."
  use Phoenix.LiveView

  def mount(_params, _session, socket), do: {:ok, socket}

  def render(assigns) do
    ~H"""
    <Chime.Components.bell chime={@chime} />
    <Chime.Components.feed chime={@chime} />
    <Chime.Components.preferences :if={@live_action == :settings} id="prefs" chime={@chime} />
    """
  end
end

defmodule ChimeTest.Host do
  @moduledoc """
  The app of the tests: the JSON API behind a pipeline of the app's with
  its session, the page to unsubscribe behind one with neither session
  nor CSRF, and LiveViews of the app with the bell.
  """

  use PhoenixMountable.TestHost,
    otp_app: :chime,
    routes:
      (quote do
         import Chime.Router
         import Phoenix.LiveView.Router

         pipeline :api do
           plug :accepts, ["json"]
           plug :fetch_session
         end

         pipeline :mail do
           plug :accepts, ["html"]
         end

         scope "/api" do
           pipe_through :api
           chime_api "/notifications"
         end

         scope "/" do
           pipe_through :mail
           chime_mail("/notifications/mail", app_name: "The app")
         end

         scope "/" do
           pipe_through :browser

           live_session :app, on_mount: [ChimeTest.AssignReader, {Chime.Live, limit: 2}] do
             live "/bell", ChimeTest.BellLive, :index
             live "/settings", ChimeTest.BellLive, :settings
           end
         end
       end)
end

defmodule ChimeTest.ConnCase do
  @moduledoc """
  Tests of the API, the page to unsubscribe and the LiveViews, through
  the test endpoint, on both databases: write them in
  `for_each_repo do ... end`, with a conn in the context.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Plug.Conn
      import Phoenix.ConnTest
      import Phoenix.LiveViewTest
      import ChimeTest.DataCase
      import ChimeTest.ConnCase
      import Swoosh.TestAssertions

      alias Chime.{Delivery, Event, Notification, Recipient}

      @endpoint ChimeTest.Host.Endpoint
    end
  end

  setup do
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc "A conn of a person, in the session."
  def as(conn, recipient), do: Phoenix.ConnTest.init_test_session(conn, %{"reader" => recipient})
end
