defmodule Chime.Components do
  @moduledoc ~S"""
  The bell, the feed and the preferences in the app's LiveViews, from
  `@chime` (`Chime.Live`):

      <Chime.Components.bell chime={@chime} />
      <Chime.Components.feed chime={@chime} />

  The bell has a dot while the person has notifications they have not
  seen, never a count unless asked (`count`); a click opens the feed,
  which marks them seen. The feed lists the notifications as their
  notifiers render them, the unread ones marked; a click on one reads it
  and goes to its `:url`.

  The markup has classes of `chime-` and no style of its own: style it
  with the app's CSS, or start from Chime's, `deps/chime/priv/static/chime.css`
  (imported into the app's: `@import "../../deps/chime/priv/static/chime.css";`).
  The words are English, as attributes: give the app's own, in its
  language.
  """

  use Phoenix.Component

  alias Chime.Live.State

  @doc "The bell, with a dot for what the person has not seen."
  attr :chime, State, required: true
  attr :count, :boolean, default: false, doc: "show the number of unread, not only a dot"
  attr :label, :string, default: "Notifications"
  attr :class, :string, default: nil

  def bell(%{chime: %State{recipient: nil}} = assigns), do: ~H""

  def bell(assigns) do
    ~H"""
    <button
      type="button"
      class={["chime-bell", @class]}
      phx-click="chime:toggle"
      aria-label={@label}
      aria-haspopup="dialog"
      aria-expanded={to_string(@chime.open)}
      data-unseen={@chime.unseen}
    >
      <svg viewBox="0 0 24 24" width="20" height="20" fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
        <path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9" /><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0" />
      </svg>
      <span :if={@chime.unseen > 0 and not @count} class="chime-dot" aria-hidden="true"></span>
      <span :if={@count and @chime.unread > 0} class="chime-count">{@chime.unread}</span>
    </button>
    """
  end

  @doc "The panel of the feed, while it is open."
  attr :chime, State, required: true
  attr :title, :string, default: "Notifications"
  attr :empty, :string, default: "Nothing yet."
  attr :read_all, :string, default: "Mark all as read"
  attr :more, :string, default: "Show more"
  attr :all, :string, default: "All"
  attr :unread, :string, default: "Unread"
  attr :archive, :string, default: "Archive"
  attr :class, :string, default: nil

  def feed(%{chime: %State{recipient: nil}} = assigns), do: ~H""
  def feed(%{chime: %State{open: false}} = assigns), do: ~H""

  def feed(assigns) do
    ~H"""
    <div class={["chime-feed", @class]} role="dialog" aria-label={@title} phx-click-away="chime:close" phx-window-keydown="chime:close" phx-key="Escape">
      <header class="chime-feed-header">
        <h2>{@title}</h2>
        <button :if={@chime.unread > 0} type="button" class="chime-read-all" phx-click="chime:read_all">{@read_all}</button>
      </header>
      <nav class="chime-filters">
        <button type="button" phx-click="chime:filter" phx-value-filter="inbox" aria-pressed={to_string(@chime.filter == :inbox)}>{@all}</button>
        <button type="button" phx-click="chime:filter" phx-value-filter="unread" aria-pressed={to_string(@chime.filter == :unread)}>{@unread}</button>
      </nav>
      <p :if={@chime.items == []} class="chime-empty">{@empty}</p>
      <ul :if={@chime.items != []} class="chime-items">
        <li :for={item <- @chime.items} id={"chime-" <> item.id} class={["chime-item", is_nil(item.notification.read_at) && "chime-unread"]} data-kind={item.notification.kind}>
          <button type="button" class="chime-item-open" phx-click="chime:visit" phx-value-id={item.id}>
            <span class="chime-item-title">{item.feed[:title]}</span>
            <span :if={item.feed[:body]} class="chime-item-body">{item.feed[:body]}</span>
            <time class="chime-item-time" datetime={DateTime.to_iso8601(item.notification.updated_at)}>{ago(item.notification.updated_at)}</time>
          </button>
          <button type="button" class="chime-item-archive" phx-click="chime:archive" phx-value-id={item.id} aria-label={@archive} title={@archive}>×</button>
        </li>
      </ul>
      <button :if={@chime.more} type="button" class="chime-more" phx-click="chime:more">{@more}</button>
    </div>
    """
  end

  @doc """
  The person's preferences: a row for each category of the config, a
  choice for each channel. A live component of its own, which keeps the
  changes as they are made.

      <Chime.Components.preferences id="notifications" chime={@chime} />
  """
  attr :id, :string, required: true
  attr :chime, State, required: true

  attr :labels, :map,
    default: %{},
    doc: "the channels' and settings' words: %{\"email\" => \"Email\", \"daily\" => \"Daily\"}"

  def preferences(%{chime: %State{recipient: nil}} = assigns), do: ~H""

  def preferences(assigns) do
    ~H"""
    <.live_component module={Chime.Components.Preferences} id={@id} recipient={@chime.recipient} labels={@labels} />
    """
  end

  @doc false
  # How long ago, in a few letters.
  def ago(%DateTime{} = at, now \\ DateTime.utc_now()) do
    seconds = DateTime.diff(now, at)

    cond do
      seconds < 60 -> "now"
      seconds < 3600 -> "#{div(seconds, 60)}m"
      seconds < 86_400 -> "#{div(seconds, 3600)}h"
      seconds < 7 * 86_400 -> "#{div(seconds, 86_400)}d"
      true -> Calendar.strftime(at, "%b %-d")
    end
  end

  defmodule Preferences do
    @moduledoc false
    # The preferences' form: Chime.Components.preferences/1.

    use Phoenix.LiveComponent

    alias Chime.Config

    @impl true
    def update(assigns, socket) do
      config = Config.get()

      {:ok,
       socket
       |> assign(assigns)
       |> assign(:channels, Config.channel_names(config))
       |> assign(:rows, Chime.preferences(assigns.recipient))
       |> assign(:error, nil)}
    end

    @impl true
    def handle_event(
          "set",
          %{"category" => category, "channel" => channel, "setting" => setting},
          socket
        ) do
      case Chime.put_preference(socket.assigns.recipient, category, channel, setting) do
        :ok ->
          {:noreply,
           assign(socket, rows: Chime.preferences(socket.assigns.recipient), error: nil)}

        {:error, code} ->
          {:noreply, assign(socket, :error, code)}
      end
    end

    @impl true
    def render(assigns) do
      ~H"""
      <div class="chime-preferences" id={@id}>
        <table>
          <thead>
            <tr>
              <th></th>
              <th :for={channel <- @channels} scope="col">{label(@labels, channel)}</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={row <- @rows} data-category={row.category.key}>
              <th scope="row">
                {row.category.label}
                <small :if={row.category.description}>{row.category.description}</small>
              </th>
              <td :for={channel <- @channels}>
                <form id={"#{@id}-#{row.category.key}-#{channel}"} phx-change="set" phx-target={@myself}>
                  <input type="hidden" name="category" value={row.category.key} />
                  <input type="hidden" name="channel" value={channel} />
                  <select name="setting" disabled={row.category.required} aria-label={"#{row.category.label}: #{label(@labels, channel)}"}>
                    <option :for={setting <- settings(channel)} value={setting} selected={row.settings[channel] == setting}>
                      {label(@labels, setting)}
                    </option>
                  </select>
                </form>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      """
    end

    defp settings("email"), do: ~w(on daily weekly off)
    defp settings(_channel), do: ~w(on off)

    defp label(labels, key),
      do: Map.get(labels, key) || key |> String.replace("_", " ") |> String.capitalize()
  end
end
