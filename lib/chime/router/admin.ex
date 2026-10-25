defmodule Chime.Router.Admin do
  @moduledoc """
  The admin, mounted with `chime_admin/2` (imported with `Chime.Router`):
  a person's notifications and their log, the events, the deliveries
  that failed and a way to send them again.

      scope "/admin" do
        pipe_through [:browser, :require_admin]

        chime_admin "/notifications",
          access: MyAppWeb.ChimeAdminAccess,
          on_mount: [{MyAppWeb.AdminAuth, :require_admin}]
      end

  `:access` is a module of `Chime.Admin.Access`, asked on the request of
  the page: Chime fails closed, and the admin is a 404 to anyone it does
  not allow. Mount it behind the app's admin pipeline and its `on_mount`
  all the same.
  """

  use PhoenixMountable,
    otp_app: :chime,
    macro: :chime_admin,
    title: "Chime",
    layout: {Chime.Admin.Layouts, :root},
    on_mount: [Chime.Admin.Auth],
    assets:
      {PhoenixMountable.Assets.Embedded,
       css: "priv/static/chime-admin.css",
       js: "priv/static/chime-admin.js",
       prepend: [:phoenix, :phoenix_live_view, :phoenix_mountable]}

  options(
    access: [
      type: :atom,
      required: true,
      verify: {:behaviour, Chime.Admin.Access},
      doc: "The app's `Chime.Admin.Access`: who may see the admin."
    ],
    otp_app: [
      type: :atom,
      doc:
        "The app whose notifiers the previews show: its modules of `Chime.Notifier` with `preview/0`. Without it, the notifiers loaded."
    ]
  )

  routes do
    live "/", Chime.Admin.HomeLive, :index
    live "/people/:recipient", Chime.Admin.PersonLive, :show
    live "/notifications/:id", Chime.Admin.NotificationLive, :show
    live "/previews", Chime.Admin.PreviewsLive, :index
    live "/previews/:notifier", Chime.Admin.PreviewsLive, :show
  end

  # Whether the request's person may see the admin, read from the request
  # of the page, after the app's own pipeline: it goes into the signed
  # session of the LiveViews.
  @impl PhoenixMountable
  def session(conn, mount, _session) do
    %{"chime_admin" => mount.options.access.allow?(conn) == true}
  end
end
