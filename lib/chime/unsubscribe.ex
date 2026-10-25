defmodule Chime.Unsubscribe do
  @moduledoc ~S"""
  The links to unsubscribe of the emails, mounted with
  `Chime.Router.chime_mail/2` at the config's `:mail_url`:

      pipeline :mail do
        plug :accepts, ["html"]
      end

      scope "/" do
        pipe_through :mail
        chime_mail "/notifications/mail", app_name: "Atelier"
      end

  An email of a notification has a link to turn off its category's
  emails (and the headers of one-click unsubscribe, RFC 8058); a digest
  has a link to turn off every email that is not required.

    * `GET /:token` - a page that asks to confirm, with a button: a mail
      client or a scanner that opens links must not unsubscribe anyone.
    * `POST /:token` - unsubscribes, and says so. A mail client's one-click
      (`List-Unsubscribe=One-Click` as the body) is this too, with no
      session and no CSRF token: mount it behind a pipeline without
      `protect_from_forgery`. The token is signed, and says who and what:
      it is the request's only credential.

  An unknown or forged token is a 404. The person can turn the emails on
  again in the app's preferences.
  """

  @behaviour Plug

  import Plug.Conn
  import Chime.Messages, only: [t: 1, t: 2]

  alias Chime.{Config, Messages, Preferences, Token}

  @impl Plug
  def init(action), do: action

  @impl Plug
  def call(conn, action) do
    config = Config.get()

    case Token.verify_unsubscribe(config, conn.path_params["token"]) do
      {:ok, recipient, category} ->
        # In the person's language, as their emails are.
        Messages.with_locale(locale(config, recipient), fn ->
          app = conn.assigns.mount.options[:app_name] || t("the app")
          handle(action, conn, config, app, recipient, category)
        end)

      :error ->
        page(conn, 404, t("Unsubscribe"), "<p>#{escape(t("This link is not valid."))}</p>")
    end
  end

  defp locale(config, recipient) do
    case config.resolver.recipients([recipient]) do
      [%{locale: locale} | _] -> locale
      _ -> nil
    end
  end

  defp handle(:show, conn, config, app, _recipient, category) do
    question =
      t("Stop the emails of %{app} about %{what}?", app: app, what: what(config, category))

    page(conn, 200, t("Unsubscribe"), """
    <p>#{escape(question)}</p>
    <form method="post" action="#{escape(conn.request_path)}">
      <button type="submit">#{escape(t("Unsubscribe"))}</button>
    </form>
    """)
  end

  defp handle(:unsubscribe, conn, config, app, recipient, category) do
    :ok = Preferences.unsubscribe(config, recipient, category)

    done =
      t(
        "You will no longer get emails of %{app} about %{what}. You can turn them on again in your settings.",
        app: app,
        what: what(config, category)
      )

    page(conn, 200, t("Unsubscribed"), "<p>#{escape(done)}</p>")
  end

  defp what(_config, "*"), do: t("anything but your account")

  defp what(config, category) do
    String.downcase(t(Config.category(config, category).label))
  rescue
    ArgumentError -> category
  end

  defp page(conn, status, title, body) do
    conn
    |> put_resp_content_type("text/html")
    |> put_resp_header("x-robots-tag", "noindex")
    |> send_resp(status, """
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="robots" content="noindex">
        <title>#{escape(title)}</title>
        <style>
          body { font: 16px/1.5 system-ui, sans-serif; max-width: 32rem; margin: 4rem auto; padding: 0 1rem; color: #1c1917; }
          button { font: inherit; padding: .5rem 1rem; border-radius: .375rem; border: 1px solid #1c1917; background: #1c1917; color: #fff; cursor: pointer; }
        </style>
      </head>
      <body>
        <h1>#{escape(title)}</h1>
        #{body}
      </body>
    </html>
    """)
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
