defmodule Chime.Admin.HomeLive do
  @moduledoc false
  # The admin's first page: the deliveries of the last day by status, the
  # ones that failed (to send again), the latest events. With ?person=,
  # that person's page.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Chime.Router.Admin

  import Chime.Admin.Layouts

  alias Chime.Admin.Data

  @impl true
  def mount(_params, _session, socket),
    do: {:ok, assign(socket, page_title: "Notifications", flash_text: nil)}

  @impl true
  def handle_params(%{"person" => person}, _uri, socket) when person != "" do
    {:noreply, push_navigate(socket, to: ~m"/people/#{String.trim(person)}")}
  end

  def handle_params(_params, _uri, socket), do: {:noreply, load(socket)}

  defp load(socket) do
    config = socket.assigns.config

    assign(socket,
      statuses: Data.statuses(config),
      failed: Data.failed(config),
      events: Data.events(config)
    )
  end

  @impl true
  def handle_event("resend", %{"id" => id}, socket) do
    text =
      case Chime.resend(id) do
        :ok -> "Sent again."
        {:error, :waiting} -> "It waits already."
        {:error, :not_found} -> "No such delivery."
      end

    {:noreply, socket |> assign(:flash_text, text) |> load()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page mount={@mount} title="Notifications">
      <p :if={@flash_text} class="flash">{@flash_text}</p>

      <h2>The last day</h2>
      <div class="tiles">
        <div :for={status <- Chime.Delivery.statuses()} class="tile" data-status={status}>
          <b>{Map.get(@statuses, status, 0)}</b>
          <.status status={status} />
        </div>
      </div>

      <h2>Failed</h2>
      <p :if={@failed == []} class="muted">None.</p>
      <table :if={@failed != []}>
        <tr><th>When</th><th>To</th><th>Kind</th><th>Channel</th><th>Error</th><th></th></tr>
        <tr :for={d <- @failed} id={"failed-" <> d.id}>
          <td>{time(d.updated_at)}</td>
          <td><.link navigate={~m"/people/#{d.recipient}"}>{d.recipient}</.link></td>
          <td><.link navigate={~m"/notifications/#{d.notification_id}"}>{d.notification.kind}</.link></td>
          <td>{d.channel}</td>
          <td><small>{d.reason}</small></td>
          <td><button phx-click="resend" phx-value-id={d.id}>Send again</button></td>
        </tr>
      </table>

      <h2>Events</h2>
      <table>
        <tr><th>When</th><th>Kind</th><th>Category</th><th>People</th><th>Status</th><th>Key</th></tr>
        <tr :for={e <- @events}>
          <td>{time(e.inserted_at)}</td>
          <td>{e.kind}</td>
          <td>{e.category}<small :if={e.workspace}> · {e.workspace}</small></td>
          <td>{e.recipients}</td>
          <td><.status status={e.status} /></td>
          <td><small>{e.key}</small></td>
        </tr>
      </table>
    </.page>
    """
  end
end
