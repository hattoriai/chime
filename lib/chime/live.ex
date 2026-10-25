defmodule Chime.Live do
  @moduledoc """
  The feed in the app's LiveViews: an `on_mount` hook that gives each
  LiveView of a `live_session` the `@chime` assign, for the components of
  `Chime.Components`.

      live_session :app,
        on_mount: [
          {MyAppWeb.UserAuth, :ensure_authenticated},
          Chime.Live
        ] do
        ...
      end

  Put it after the app's own hooks: the config's resolver reads the
  person from the socket's assigns (`c:Chime.Resolver.resolve_recipient/1`).
  Options, as `{Chime.Live, limit: 20}`:

    * `:limit` - the notifications of the panel, and of each "Show more"
      (10).

  `@chime` (`Chime.Live.State`) holds the person, their counts, and, once
  the panel is open, its notifications. It stays live: a notification
  that comes reaches every open page of the person at once, with no
  query but their own, and seeing or reading in one tab clears the
  others. For nobody (the resolver gives nil), `@chime.recipient` is nil
  and the components render nothing.

  The events `chime:toggle`, `chime:open` and `chime:close` open the panel
  (which marks the feed seen) and close it; `chime:more` loads more;
  `chime:filter` (`%{"filter" => "unread"}` or `"inbox"`) shows the
  unread or all; `chime:read` and `chime:archive` (`%{"id" => id}`) mark
  one; `chime:read_all` marks them all read; `chime:visit` (`%{"id" =>
  id}`) marks one read and goes to its `:url`. The components send them,
  and a LiveView's own buttons can too (`phx-click="chime:toggle"`). The
  hook handles them, and the messages of the PubSub, before the LiveView
  sees them.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView

  alias Chime.{Config, Counts, Feed, Resolver}

  defmodule State do
    @moduledoc """
    The `@chime` assign:

      * `:recipient` - the person's id, or nil for nobody;
      * `:unseen` and `:unread` - their counts;
      * `:open` - whether the panel is open; `:items` - its notifications,
        each `%{id:, notification:, feed:}`, the feed as the notifier
        renders it; `:more` - whether there are more; `:filter` -
        `:inbox` or `:unread`;
      * `:limit` - the notifications of a page.
    """

    @type t :: %__MODULE__{
            recipient: String.t() | nil,
            unseen: non_neg_integer(),
            unread: non_neg_integer(),
            open: boolean(),
            items: [map()],
            more: boolean(),
            filter: :inbox | :unread,
            limit: pos_integer()
          }

    defstruct recipient: nil,
              unseen: 0,
              unread: 0,
              open: false,
              items: [],
              more: false,
              filter: :inbox,
              limit: 10
  end

  @doc false
  def on_mount(:default, params, session, socket), do: on_mount([], params, session, socket)

  def on_mount(opts, _params, _session, socket) when is_list(opts) do
    config = Config.get()
    recipient = Resolver.reader(config.resolver, socket)
    state = %State{recipient: recipient, limit: Keyword.get(opts, :limit, 10)}

    cond do
      recipient == nil ->
        {:cont, assign(socket, :chime, state)}

      connected?(socket) ->
        Chime.subscribe(recipient)

        socket =
          socket
          |> attach_hook(:chime_events, :handle_event, &handle_event/3)
          |> attach_hook(:chime_info, :handle_info, &handle_info/2)

        {:cont, assign(socket, :chime, with_counts(state, Counts.get(config, recipient)))}

      true ->
        {:cont, assign(socket, :chime, with_counts(state, Counts.get(config, recipient)))}
    end
  end

  defp handle_event("chime:toggle", _params, socket) do
    if socket.assigns.chime.open,
      do: handle_event("chime:close", %{}, socket),
      else: handle_event("chime:open", %{}, socket)
  end

  defp handle_event("chime:open", _params, socket) do
    update(socket, fn state ->
      counts = Chime.mark_seen(state.recipient)
      state |> with_counts(counts) |> Map.put(:open, true) |> load(state.limit)
    end)
  end

  defp handle_event("chime:close", _params, socket),
    do: update(socket, &%{&1 | open: false, items: [], more: false})

  defp handle_event("chime:more", _params, socket),
    do: update(socket, &load(&1, length(&1.items) + &1.limit))

  defp handle_event("chime:filter", %{"filter" => filter}, socket) do
    filter = if filter == "unread", do: :unread, else: :inbox
    update(socket, &load(%{&1 | filter: filter}, &1.limit))
  end

  defp handle_event("chime:read", %{"id" => id}, socket), do: mark(socket, :read, [id])
  defp handle_event("chime:archive", %{"id" => id}, socket), do: mark(socket, :archive, [id])
  defp handle_event("chime:read_all", _params, socket), do: mark(socket, :read, :all)

  defp handle_event("chime:visit", %{"id" => id}, socket) do
    # The item before the mark: under the unread filter, it then leaves the list.
    item = Enum.find(socket.assigns.chime.items, &(&1.id == id))
    {:halt, socket} = mark(socket, :read, [id])

    case item do
      %{feed: %{url: "/" <> _ = path}} -> {:halt, push_navigate(socket, to: path)}
      %{feed: %{url: "http" <> _ = url}} -> {:halt, redirect(socket, external: url)}
      _ -> {:halt, socket}
    end
  end

  defp handle_event(_event, _params, socket), do: {:cont, socket}

  # A notification came: the counts, and the panel's list when it is open,
  # seen at once as the person looks at it.
  defp handle_info({Chime, :notified, counts}, socket) do
    state = socket.assigns.chime

    if state.open do
      counts = Chime.mark_seen(state.recipient)

      {:halt,
       assign(
         socket,
         :chime,
         state |> with_counts(counts) |> load(max(length(state.items), state.limit))
       )}
    else
      {:halt, assign(socket, :chime, with_counts(state, counts))}
    end
  end

  defp handle_info({Chime, :updated, counts}, socket) do
    state = with_counts(socket.assigns.chime, counts)
    state = if state.open, do: load(state, max(length(state.items), state.limit)), else: state
    {:halt, assign(socket, :chime, state)}
  end

  defp handle_info(_message, socket), do: {:cont, socket}

  defp mark(socket, action, ids) do
    update(socket, fn state ->
      counts = Feed.mark(Config.get(), state.recipient, action, ids)
      state |> with_counts(counts) |> load(max(length(state.items), state.limit))
    end)
  end

  defp update(socket, fun), do: {:halt, assign(socket, :chime, fun.(socket.assigns.chime))}

  defp with_counts(state, %{unseen: unseen, unread: unread}),
    do: %{state | unseen: unseen, unread: unread}

  defp load(%State{} = state, limit) do
    notifications =
      Feed.list(Config.get(), state.recipient, limit: limit + 1, filter: state.filter)

    items =
      notifications
      |> Enum.take(limit)
      |> Enum.map(&%{id: &1.id, notification: &1, feed: Feed.render(&1)})

    %{state | items: items, more: length(notifications) > limit}
  end
end
