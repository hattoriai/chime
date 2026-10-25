defmodule Chime.Admin.PersonLive do
  @moduledoc false
  # A person's page: their counts, notifications and each one's
  # deliveries, their preferences and devices.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Chime.Router.Admin

  import Chime.Admin.Layouts

  alias Chime.Admin.Data

  @impl true
  def mount(%{"recipient" => recipient}, _session, socket) do
    config = socket.assigns.config

    {:ok,
     assign(socket,
       page_title: recipient,
       recipient: recipient,
       counts: Chime.counts(recipient),
       notifications: Data.notifications(config, recipient),
       preferences: Chime.preferences(recipient),
       devices: Chime.devices(recipient),
       channels: Chime.Config.channel_names(config)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.page mount={@mount} title={@recipient}>
      <div class="tiles">
        <div class="tile"><b>{@counts.unseen}</b><small>not seen</small></div>
        <div class="tile"><b>{@counts.unread}</b><small>not read</small></div>
        <div class="tile"><b>{length(@devices)}</b><small>devices</small></div>
      </div>

      <h2>Notifications</h2>
      <p :if={@notifications == []} class="muted">None.</p>
      <table :if={@notifications != []}>
        <tr><th>When</th><th>Kind</th><th>Feed</th><th>Deliveries</th></tr>
        <tr :for={n <- @notifications} id={"n-" <> n.id}>
          <td>{time(n.updated_at)}</td>
          <td>
            <.link navigate={~m"/notifications/#{n.id}"}>{n.kind}</.link>
            <small :if={n.count > 1}> ×{n.count}</small>
            <small :if={n.workspace}> · {n.workspace}</small>
          </td>
          <td>
            <.status status={feed_status(n)} />
          </td>
          <td>
            <span :for={d <- n.deliveries} title={d.reason}>{d.channel} <.status status={d.status} /> </span>
          </td>
        </tr>
      </table>

      <h2 :if={@preferences != []}>Preferences</h2>
      <table :if={@preferences != []}>
        <tr><th></th><th :for={c <- @channels}>{c}</th></tr>
        <tr :for={row <- @preferences}>
          <th>{row.category.label}</th>
          <td :for={c <- @channels}>{row.settings[c]}</td>
        </tr>
      </table>

      <h2 :if={@devices != []}>Devices</h2>
      <table :if={@devices != []}>
        <tr><th>Kind</th><th>Name</th><th>On</th><th>Last push</th></tr>
        <tr :for={d <- @devices}>
          <td>{d.kind}</td>
          <td>{d.name}</td>
          <td>{if d.enabled, do: "on", else: "off"}</td>
          <td>{time(d.last_used_at)}</td>
        </tr>
      </table>
    </.page>
    """
  end

  defp feed_status(%{in_feed: false}), do: "skipped"
  defp feed_status(%{archived_at: at}) when at != nil, do: "archived"
  defp feed_status(%{read_at: at}) when at != nil, do: "read"
  defp feed_status(%{seen_at: at}) when at != nil, do: "seen"
  defp feed_status(_n), do: "shown"
end
