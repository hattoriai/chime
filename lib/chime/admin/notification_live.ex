defmodule Chime.Admin.NotificationLive do
  @moduledoc false
  # A notification's page: what it says, its data, and its log
  # (Chime.Explain), each delivery that failed or was skipped with a way to
  # send it again.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Chime.Router.Admin

  import Chime.Admin.Layouts

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> {:ok, socket |> assign(id: id, flash_text: nil) |> load()}
      :error -> raise Chime.Admin.NotFound
    end
  end

  defp load(socket) do
    case Chime.explain(socket.assigns.id) do
      nil ->
        raise Chime.Admin.NotFound

      %{notification: n} = log ->
        assign(socket,
          page_title: n.kind,
          log: log,
          notification: n,
          feed: Chime.Feed.render(n),
          text: Chime.Explain.format(log)
        )
    end
  end

  @impl true
  def handle_event("resend", %{"id" => id}, socket) do
    text = if Chime.resend(id) == :ok, do: "Sent again.", else: "It cannot be sent again now."
    {:noreply, socket |> assign(:flash_text, text) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page mount={@mount} title={@feed[:title] || @notification.kind}>
      <p :if={@flash_text} class="flash">{@flash_text}</p>
      <p class="muted">
        {@notification.kind} to
        <.link navigate={~m"/people/#{@notification.recipient}"}>{@notification.recipient}</.link>
        · {@notification.category}
        <span :if={@notification.workspace}>· {@notification.workspace}</span>
        <span :if={@notification.count > 1}>· {@notification.count} events</span>
      </p>

      <h2>The log</h2>
      <table>
        <tr><th>When</th><th>Channel</th><th>Status</th><th>Why</th></tr>
        <tr :for={step <- @log.steps}>
          <td>{time(step.at)}</td>
          <td>{step.channel}</td>
          <td><.status status={step.status} /></td>
          <td><small>{step.reason}</small></td>
        </tr>
      </table>

      <h2>Deliveries</h2>
      <table>
        <tr><th>Channel</th><th>Status</th><th>Attempts</th><th>Ref</th><th></th></tr>
        <tr :for={d <- @notification.deliveries} id={"d-" <> d.id}>
          <td>{d.channel}</td>
          <td><.status status={d.status} /></td>
          <td>{d.attempts}</td>
          <td><small>{d.ref}</small></td>
          <td>
            <button :if={d.status in ["failed", "skipped"] and d.channel != "feed"} phx-click="resend" phx-value-id={d.id}>
              Send again
            </button>
          </td>
        </tr>
      </table>

      <h2>The data</h2>
      <pre>{JSON.encode!(@notification.event.data)}</pre>

      <h2>As text</h2>
      <pre>{@text}</pre>
    </.page>
    """
  end
end
