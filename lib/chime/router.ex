defmodule Chime.Router do
  @moduledoc """
  Mounts Chime in the app's router.

      import Chime.Router

      scope "/api" do
        pipe_through :api_authenticated
        chime_api "/notifications"
      end

      # The links to unsubscribe of the emails: no session, no CSRF token,
      # as a mail client posts them (RFC 8058).
      pipeline :unsubscribe do
        plug :accepts, ["html"]
      end

      scope "/" do
        pipe_through :unsubscribe
        chime_unsubscribe "/notifications/unsubscribe"
      end

  `chime_api/2` mounts the feed and the preferences as JSON, for a
  frontend that Phoenix does not render (see `Chime.API` and the
  [Any frontend](any_frontend.md) guide), and `chime_unsubscribe/2` the
  page of the links to unsubscribe (see `Chime.Unsubscribe`), at the
  config's `:unsubscribe_url`. Each is a library mounted with
  [PhoenixMountable](https://hexdocs.pm/phoenix_mountable): ordinary
  routes in the app's router (`mix phx.routes` lists them), behind the
  app's own scopes and pipelines.

  The LiveViews of the app need no mount: `Chime.Live` and
  `Chime.Components` go in them.
  """

  alias Chime.Router.Unsubscribe

  use PhoenixMountable,
    otp_app: :chime,
    macro: :chime_api,
    schema: Chime.Migrations

  options(
    token_max_age: [
      type: :pos_integer,
      default: 86_400,
      doc: "How long a token of `Chime.Token` is valid, in seconds."
    ]
  )

  routes do
    get "/", Chime.API, :index
    get "/counts", Chime.API, :counts, as: :counts
    post "/seen", Chime.API, :seen, as: :seen
    post "/read", Chime.API, :read_all, as: :read_all
    get "/preferences", Chime.API, :preferences, as: :preferences
    put "/preferences", Chime.API, :put_preferences, as: :put_preferences
    get "/stream", Chime.API, :stream, as: :stream
    post "/token", Chime.API, :token, as: :token
    post "/:id/read", Chime.API, :read, as: :read
    post "/:id/unread", Chime.API, :unread, as: :unread
    post "/:id/archive", Chime.API, :archive, as: :archive
    post "/:id/unarchive", Chime.API, :unarchive, as: :unarchive
  end

  @impl PhoenixMountable
  def repo(_mount) do
    Chime.Config.get().repo
  rescue
    RuntimeError -> nil
  end

  @doc """
  Mounts the page of the links to unsubscribe at `path`: see
  `Chime.Unsubscribe`.
  """
  defmacro chime_unsubscribe(path, opts \\ []) do
    quote do
      require unquote(Unsubscribe)
      unquote(Unsubscribe).chime_unsubscribe(unquote(path), unquote(opts))
    end
  end
end
