defmodule Chime.Admin.Layouts do
  @moduledoc false
  # The admin's own document, and the shell of its pages.

  use Phoenix.Component
  use PhoenixMountable.Path, mountable: Chime.Router.Admin

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="color-scheme" content="light dark" />
        <meta name="robots" content="noindex, nofollow" />
        <PhoenixMountable.Layout.meta mount={@mount} />
        <title>{assigns[:page_title] || "Notifications"} · Chime</title>
        <PhoenixMountable.Layout.assets mount={@mount} />
      </head>
      <body class="chime-admin">
        {@inner_content}
      </body>
    </html>
    """
  end

  attr :mount, :any, required: true
  attr :title, :string, required: true
  slot :inner_block, required: true

  def page(assigns) do
    ~H"""
    <header class="bar">
      <.link navigate={~m"/"} class="brand">Chime</.link>
      <.link navigate={~m"/previews"}>Previews</.link>
      <form action={~m"/"} method="get" class="find">
        <input type="search" name="person" placeholder="A person's id: user:42" aria-label="Find a person" />
      </form>
    </header>
    <main>
      <h1>{@title}</h1>
      {render_slot(@inner_block)}
    </main>
    """
  end

  attr :status, :string, required: true

  def status(assigns) do
    ~H"""
    <span class={["status", "status-#{@status}"]}>{@status}</span>
    """
  end

  def time(%DateTime{} = at),
    do: at |> DateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M:%SZ")

  def time(nil), do: ""
end
