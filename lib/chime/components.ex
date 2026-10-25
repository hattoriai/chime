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
  The words are Chime's, in the app's languages by its Gettext (see
  `Chime.Messages`); each is an attribute too, for words of the app's
  own.
  """

  use Phoenix.Component

  import Chime.Messages, only: [t: 1, t: 2]

  alias Chime.Live.State

  @doc "The bell, with a dot for what the person has not seen."
  attr :chime, State, required: true
  attr :count, :boolean, default: false, doc: "show the number of unread, not only a dot"
  attr :label, :string, default: nil, doc: "\"Notifications\""
  attr :class, :string, default: nil

  def bell(%{chime: %State{recipient: nil}} = assigns), do: ~H""

  def bell(assigns) do
    ~H"""
    <button
      type="button"
      class={["chime-bell", @class]}
      phx-click="chime:toggle"
      aria-label={@label || t("Notifications")}
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
  attr :title, :string, default: nil, doc: "\"Notifications\""
  attr :empty, :string, default: nil, doc: "\"Nothing yet.\""
  attr :read_all, :string, default: nil, doc: "\"Mark all as read\""
  attr :more, :string, default: nil, doc: "\"Show more\""
  attr :all, :string, default: nil, doc: "\"All\""
  attr :unread, :string, default: nil, doc: "\"Unread\""
  attr :archive, :string, default: nil, doc: "\"Archive\""
  attr :class, :string, default: nil

  def feed(%{chime: %State{recipient: nil}} = assigns), do: ~H""
  def feed(%{chime: %State{open: false}} = assigns), do: ~H""

  def feed(assigns) do
    assigns =
      assigns
      |> assign(:title, assigns.title || t("Notifications"))
      |> assign(:empty, assigns.empty || t("Nothing yet."))
      |> assign(:read_all, assigns.read_all || t("Mark all as read"))
      |> assign(:more, assigns.more || t("Show more"))
      |> assign(:all, assigns.all || t("All"))
      |> assign(:unread, assigns.unread || t("Unread"))
      |> assign(:archive, assigns.archive || t("Archive"))

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
          <div :if={item.feed[:actions] && is_nil(item.notification.action)} class="chime-item-actions">
            <button :for={a <- item.feed[:actions]} type="button" class="chime-action" phx-click="chime:action" phx-value-id={item.id} phx-value-action={a.key} data-action={a.key}>
              {a[:label] || a.key}
            </button>
          </div>
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
      seconds < 60 -> t("now")
      seconds < 3600 -> t("%{count}m", count: div(seconds, 60))
      seconds < 86_400 -> t("%{count}h", count: div(seconds, 3600))
      seconds < 7 * 86_400 -> t("%{count}d", count: div(seconds, 86_400))
      true -> Calendar.strftime(at, t("%b %-d"), abbreviated_month_names: &month/1)
    end
  end

  defp month(1), do: t("Jan")
  defp month(2), do: t("Feb")
  defp month(3), do: t("Mar")
  defp month(4), do: t("Apr")
  defp month(5), do: t("May")
  defp month(6), do: t("Jun")
  defp month(7), do: t("Jul")
  defp month(8), do: t("Aug")
  defp month(9), do: t("Sep")
  defp month(10), do: t("Oct")
  defp month(11), do: t("Nov")
  defp month(12), do: t("Dec")

  defmodule Preferences do
    @moduledoc false
    # The preferences' form: Chime.Components.preferences/1.

    use Phoenix.LiveComponent

    import Chime.Messages, only: [t: 1]

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
                {t(row.category.label)}
                <small :if={row.category.description}>{t(row.category.description)}</small>
              </th>
              <td :for={channel <- @channels}>
                <form id={"#{@id}-#{row.category.key}-#{channel}"} phx-change="set" phx-target={@myself}>
                  <input type="hidden" name="category" value={row.category.key} />
                  <input type="hidden" name="channel" value={channel} />
                  <select name="setting" disabled={row.category.required} aria-label={"#{t(row.category.label)}: #{label(@labels, channel)}"}>
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

    defp label(labels, key), do: Map.get(labels, key) || word(key)

    defp word("feed"), do: t("Feed")
    defp word("email"), do: t("Email")
    defp word("on"), do: t("On")
    defp word("off"), do: t("Off")
    defp word("daily"), do: t("Daily")
    defp word("weekly"), do: t("Weekly")
    defp word(key), do: key |> String.replace("_", " ") |> String.capitalize() |> t()
  end
end
