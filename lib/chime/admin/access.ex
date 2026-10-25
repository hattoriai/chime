defmodule Chime.Admin.Access do
  @moduledoc ~S"""
  Who may see Chime's admin (`Chime.Router.Admin`): the app writes one
  module, from its own admins.

      defmodule MyAppWeb.ChimeAdminAccess do
        @behaviour Chime.Admin.Access

        @impl true
        def allow?(conn), do: match?(%MyApp.Admin{}, conn.assigns[:current_admin])
      end

  `c:allow?/1` gets the `Plug.Conn` of the page, after the app's own
  pipeline. Anything but `true` is a no: the admin is a 404.
  """

  @doc "Whether the request's person may see the admin."
  @callback allow?(Plug.Conn.t()) :: boolean()
end
