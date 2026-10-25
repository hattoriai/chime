defmodule Chime.Router.Mail do
  @moduledoc """
  The addresses of the emails' links, mounted with `chime_mail/2`
  (imported with `Chime.Router`) at the config's `:mail_url`: to
  unsubscribe (`Chime.Unsubscribe`), and to open a notification, which
  reads it (`Chime.Links`).
  """

  use PhoenixMountable, otp_app: :chime, macro: :chime_mail

  options(
    app_name: [
      type: :string,
      doc: "The app's name, in the page's title and words (\"the app\")."
    ]
  )

  routes do
    get "/unsubscribe/:token", Chime.Unsubscribe, :show
    post "/unsubscribe/:token", Chime.Unsubscribe, :unsubscribe, as: :unsubscribe
    get "/open/:token", Chime.Links, :open, as: :open
  end
end
