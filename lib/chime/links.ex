defmodule Chime.Links do
  @moduledoc ~S"""
  Links that open a notification from an email or a channel, and read it
  in the feed: the same notification is read everywhere.

      def email(data, _recipient, notification) do
        Swoosh.Email.new(subject: "New comment")
        |> Swoosh.Email.html_body(~s(<a href="#{Chime.link(notification, "/stories/#{data["story_id"]}")}">Read it</a>))
      end

  `Chime.link/2` gives an address of `chime_mail` (the config's
  `:mail_url`), signed, that says the notification, its person and where
  to go. Opened, it marks the notification read (and seen) and its time
  in `:clicked_at`, tells the person's open pages, and redirects. The
  address is in the token, so the link cannot be made to send anyone
  elsewhere; a path goes on the config's `:url`. The `:email` channel
  gives each email the link of the notification's feed `:url` too, as
  `assigns.link`.

  An unknown or forged token is a 404.
  """

  @behaviour Plug

  import Plug.Conn

  alias Chime.{Config, Feed, Notification, Token}

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, :open) do
    config = Config.get()

    with {:ok, id, recipient, url} <- Token.verify_open(config, conn.path_params["token"]),
         %Notification{} <-
           config.repo.get_by(Notification, [id: id, recipient: recipient], prefix: config.prefix) do
      Feed.mark(config, recipient, :click, [id])

      conn
      |> put_resp_header("location", address(config, url))
      |> put_resp_header("x-robots-tag", "noindex")
      |> send_resp(302, "")
    else
      _ -> send_resp(conn, 404, "Not found")
    end
  end

  @doc false
  # Where a link goes: an address whole, or a path on the app's :url.
  def address(_config, "http" <> _ = url), do: url
  def address(%Config{url: nil}, path), do: path
  def address(%Config{url: base}, "/" <> _ = path), do: base <> path
  def address(_config, path), do: path
end
