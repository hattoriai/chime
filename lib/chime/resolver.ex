defmodule Chime.Resolver do
  @moduledoc ~S"""
  How Chime knows the people of the app. The app writes one module, from
  the users it already has, and gives it to Chime's config:

      defmodule MyApp.ChimeResolver do
        @behaviour Chime.Resolver

        import Ecto.Query

        alias MyApp.{Repo, User}

        @impl true
        def recipient(%User{} = user) do
          %Chime.Recipient{
            id: "user:#{user.id}",
            email: user.email,
            name: user.name,
            locale: user.locale,
            time_zone: user.time_zone
          }
        end

        @impl true
        def recipients(ids) do
          ids = for "user:" <> id <- ids, do: String.to_integer(id)

          from(u in User, where: u.id in ^ids and is_nil(u.deleted_at))
          |> Repo.all()
          |> Enum.map(&recipient/1)
        end

        @impl true
        def resolve_recipient(%Plug.Conn{assigns: %{current_user: %User{} = user}}),
          do: recipient(user)

        def resolve_recipient(%Phoenix.LiveView.Socket{assigns: %{current_user: %User{} = user}}),
          do: recipient(user)

        def resolve_recipient(_nobody), do: nil
      end

  `c:recipient/1` turns what a notifier's `recipients/1` gives (the app's
  users) into a `Chime.Recipient`. `c:recipients/1` finds the people by
  their ids when a delivery goes, which may be later than the
  notification (an email ten minutes after, a digest the next morning),
  so that it writes to their address of then; a person it does not give
  back gets nothing, and the log says why. `c:resolve_recipient/1` says
  who reads the feed: from a `Plug.Conn` (the JSON API, after the app's
  own pipeline) or a LiveView socket (`Chime.Live`, after the app's own
  `on_mount` hooks). Nil is nobody: the API answers 401, and the bell is
  not shown.

  Make the ids from the database, never from what a browser sends.
  """

  @doc "The recipient of something a notifier's `recipients/1` gives."
  @callback recipient(term()) :: Chime.Recipient.t()

  @doc "The people of these ids that still are, in any order."
  @callback recipients([String.t()]) :: [Chime.Recipient.t()]

  @doc "The person of a request or a LiveView, or nil."
  @callback resolve_recipient(Plug.Conn.t() | Phoenix.LiveView.Socket.t()) ::
              Chime.Recipient.t() | nil

  @doc """
  The workspace of a request or a LiveView (a team, an organisation of
  the app's), or nil for the whole feed. With it, the bell, the feed, its
  counts and the preferences of `Chime.Live` and the JSON API are that
  workspace's. Without this function, the whole feed.
  """
  @callback resolve_workspace(Plug.Conn.t() | Phoenix.LiveView.Socket.t()) :: String.t() | nil

  @optional_callbacks recipient: 1, resolve_workspace: 1

  @doc false
  # The recipient of what a notifier gives: a recipient as it is, an id,
  # or the app's own term through the resolver.
  @spec to_recipient(module(), term()) :: Chime.Recipient.t() | String.t()
  def to_recipient(_resolver, %Chime.Recipient{} = recipient), do: recipient
  def to_recipient(_resolver, id) when is_binary(id), do: id

  def to_recipient(resolver, term) do
    if Code.ensure_loaded?(resolver) and function_exported?(resolver, :recipient, 1) do
      case resolver.recipient(term) do
        %Chime.Recipient{} = recipient ->
          recipient

        other ->
          raise ArgumentError,
                "#{inspect(resolver)}.recipient/1 must return a %Chime.Recipient{}, got: #{inspect(other)}"
      end
    else
      raise ArgumentError,
            "a notifier gave #{inspect(term)}, which is not a %Chime.Recipient{} or an id: " <>
              "write recipient/1 in #{inspect(resolver)} to turn it into one"
    end
  end

  @doc false
  # The id of a recipient or an id.
  @spec id(Chime.Recipient.t() | String.t()) :: String.t()
  def id(%Chime.Recipient{id: id}), do: id
  def id(id) when is_binary(id), do: id

  @doc false
  # The workspace of a request or a socket, or nil.
  @spec workspace(module(), Plug.Conn.t() | Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def workspace(resolver, conn_or_socket) do
    if Code.ensure_loaded?(resolver) and function_exported?(resolver, :resolve_workspace, 1) do
      case resolver.resolve_workspace(conn_or_socket) do
        nil -> nil
        workspace -> to_string(workspace)
      end
    end
  end

  @doc false
  # The reader of a request or a socket, as an id, or nil.
  @spec reader(module(), Plug.Conn.t() | Phoenix.LiveView.Socket.t()) :: String.t() | nil
  def reader(resolver, conn_or_socket) do
    case resolver.resolve_recipient(conn_or_socket) do
      %Chime.Recipient{id: id} when is_binary(id) -> id
      id when is_binary(id) -> id
      nil -> nil
    end
  end
end
