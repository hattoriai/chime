defmodule Chime.Router.Unsubscribe do
  @moduledoc """
  The page of the links to unsubscribe, mounted with `chime_unsubscribe/2`
  (imported with `Chime.Router`). See `Chime.Unsubscribe`.
  """

  use PhoenixMountable, otp_app: :chime, macro: :chime_unsubscribe

  options(
    app_name: [
      type: :string,
      doc: "The app's name, in the page's title and words (\"the app\")."
    ]
  )

  routes do
    get "/:token", Chime.Unsubscribe, :show
    post "/:token", Chime.Unsubscribe, :unsubscribe, as: :unsubscribe
  end
end
