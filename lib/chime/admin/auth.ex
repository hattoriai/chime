defmodule Chime.Admin.NotFound do
  @moduledoc false
  defexception plug_status: 404, message: "not found"
end

defmodule Chime.Admin.Auth do
  @moduledoc false
  # The on_mount of the admin's live session, after the app's: the session
  # says whether the request of the page was allowed (Chime.Router.Admin's
  # session/3); everyone else gets a 404.

  def on_mount(:default, _params, session, socket) do
    if session["chime_admin"] == true,
      do: {:cont, Phoenix.Component.assign(socket, :config, Chime.Config.get())},
      else: raise(Chime.Admin.NotFound)
  end
end
