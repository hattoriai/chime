defmodule Chime.Admin.PreviewsLive do
  @moduledoc false
  # The notifiers of the app with previews, and each one as its channels
  # say it.

  use Phoenix.LiveView
  use PhoenixMountable.Path, mountable: Chime.Router.Admin

  import Chime.Admin.Layouts

  alias Chime.Preview

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, notifiers: Preview.notifiers(socket.assigns.mount.options[:otp_app]))}
  end

  @impl true
  def handle_params(%{"notifier" => name} = params, _uri, socket) do
    case Enum.find(socket.assigns.notifiers, &(inspect(&1) == name)) do
      nil ->
        raise Chime.Admin.NotFound

      notifier ->
        examples = Preview.examples(notifier)

        index =
          params
          |> Map.get("example", "0")
          |> Integer.parse()
          |> then(fn
            {i, _} -> i
            :error -> 0
          end)

        {label, example} = Enum.at(examples, index) || hd(examples)

        {:noreply,
         assign(socket,
           page_title: inspect(notifier),
           notifier: notifier,
           examples: examples,
           index: index,
           label: label,
           preview: Preview.render(notifier, example)
         )}
    end
  end

  def handle_params(_params, _uri, socket),
    do: {:noreply, assign(socket, page_title: "Previews", notifier: nil)}

  @impl true
  def render(%{notifier: nil} = assigns) do
    ~H"""
    <.page mount={@mount} title="Previews">
      <p :if={@notifiers == []} class="muted">
        No notifier has a preview: give one a <code>preview/0</code>.
      </p>
      <table :if={@notifiers != []}>
        <tr><th>Notifier</th><th>Kind</th><th>Category</th><th>Channels</th></tr>
        <tr :for={n <- @notifiers}>
          <td><.link navigate={~m"/previews/#{inspect(n)}"}>{inspect(n)}</.link></td>
          <td>{n.__chime__(:kind)}</td>
          <td>{n.__chime__(:category)}</td>
          <td>{Enum.map_join(n.__chime__(:deliveries), ", ", & &1.channel)}</td>
        </tr>
      </table>
    </.page>
    """
  end

  def render(assigns) do
    ~H"""
    <.page mount={@mount} title={inspect(@notifier)}>
      <p :if={length(@examples) > 1} class="examples">
        <.link :for={{{name, _}, i} <- Enum.with_index(@examples)} patch={~m"/previews/#{inspect(@notifier)}?example=#{i}"} aria-current={i == @index && "page"}>
          {name}
        </.link>
      </p>

      <div :if={@preview.feed}>
        <h2>Feed</h2>
        <.feed_item feed={@preview.feed} />
      </div>

      <div :if={@preview.group}>
        <h2>Feed, a group of three</h2>
        <.feed_item feed={@preview.group} />
      </div>

      <div :if={@preview.email}>
        <h2>Email</h2>
        <.email email={@preview.email} />
      </div>

      <div :for={{channel, said} <- @preview.others}>
        <h2>{channel}</h2>
        <pre>{inspect(said, pretty: true)}</pre>
      </div>

      <h2>The data</h2>
      <pre>{JSON.encode!(@preview.data)}</pre>
    </.page>
    """
  end

  defp feed_item(%{feed: {:error, _}} = assigns),
    do: ~H"<pre class='error'>{elem(@feed, 1)}</pre>"

  defp feed_item(assigns) do
    ~H"""
    <div class="tile preview-feed">
      <b>{@feed[:title]}</b>
      <div :if={@feed[:body]}>{@feed[:body]}</div>
      <small :if={@feed[:url]}>{@feed[:url]}</small>
      <div :if={@feed[:actions]}>
        <button :for={a <- @feed[:actions]} disabled>{a[:label] || a.key}</button>
      </div>
    </div>
    """
  end

  defp email(%{email: {:error, _}} = assigns), do: ~H"<pre class='error'>{elem(@email, 1)}</pre>"

  defp email(assigns) do
    ~H"""
    <p><b>{@email.subject}</b></p>
    <iframe :if={@email.html_body} srcdoc={@email.html_body} sandbox="" title="The email"></iframe>
    <pre :if={@email.text_body}>{@email.text_body}</pre>
    """
  end
end
