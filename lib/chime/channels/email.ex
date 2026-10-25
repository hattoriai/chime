defmodule Chime.Channels.Email do
  @moduledoc """
  The `:email` channel: the notifier's `c:Chime.Notifier.email/3`, sent
  with the app's mailer (`:mailer` in `Chime.Config`).

  The notifier gives the subject and the body. Chime gives the email:

    * its `To:`, the person's address and name (a person with no address
      is skipped, and the log says so);
    * its `From:`, the config's `:email_from`, unless the notifier set one;
    * unless the notification is required, the headers of one-click
      unsubscribe (RFC 8058), which Gmail and Yahoo ask of a sender of
      many emails: `List-Unsubscribe` with the address of the person's
      link, and `List-Unsubscribe-Post`. The same address is in the
      email's `assigns` as `:unsubscribe_url`, for a link in its footer,
      and the notifier's email can use `Chime.unsubscribe_url/2`. They
      need `:mail_url` and `:secret_key_base` in the config;
    * the link that opens the notification and reads it in the feed, from
      the feed's `:url`, in `assigns` as `:link` (`Chime.link/2`).

  The mailer's id of the email (`{:ok, %{id: id}}`) is kept as the
  delivery's ref, to match the provider's events later.
  """

  @behaviour Chime.Channel

  alias Chime.{Config, Message, Token}

  # Swoosh is an optional dependency, with the :mailer option.
  @compile {:no_warn_undefined, [Swoosh.Email]}

  @impl Chime.Channel
  def deliver(%Message{recipient: %{email: email}}, _opts) when email in [nil, ""],
    do: {:skip, "the person has no email address"}

  def deliver(%Message{} = message, _opts) do
    case Config.get() do
      %Config{mailer: nil} ->
        {:skip, "Chime's config has no :mailer"}

      config ->
        deliver(
          message,
          config,
          message.notifier.email(message.data, message.recipient, message.notification)
        )
    end
  end

  defp deliver(message, config, email) do
    case email do
      %{__struct__: Swoosh.Email} = email ->
        email
        |> link(message)
        |> address(config, message)
        |> unsubscribe(config, message, message.category)
        |> send_email(config)

      other ->
        raise ArgumentError,
              "#{inspect(message.notifier)}.email/3 must return a Swoosh.Email, got: #{inspect(other)}"
    end
  end

  # The link that opens the notification (and reads it), from the feed's
  # :url, for the email's templates.
  defp link(email, %{notifier: notifier, data: data, notification: notification}) do
    case Chime.Feed.render(notifier, data, notification) do
      %{url: url} when is_binary(url) ->
        Swoosh.Email.assign(email, :link, Chime.link(notification, url))

      _ ->
        email
    end
  end

  @doc false
  # The To: and From: of an email to a person.
  def address(email, config, %{recipient: recipient}) do
    email =
      Swoosh.Email.to(
        email,
        if(recipient.name, do: {recipient.name, recipient.email}, else: recipient.email)
      )

    if email.from in [nil, {"", ""}], do: Swoosh.Email.from(email, config.email_from), else: email
  end

  @doc false
  # The headers and the address to unsubscribe, unless the email is
  # required.
  def unsubscribe(email, _config, %{required: true}, _category), do: email

  def unsubscribe(email, config, %{recipient: recipient}, category) do
    case Token.unsubscribe_url(config, recipient.id, category) do
      nil ->
        email

      url ->
        email
        |> Swoosh.Email.header("List-Unsubscribe", "<#{url}>")
        |> Swoosh.Email.header("List-Unsubscribe-Post", "List-Unsubscribe=One-Click")
        |> Swoosh.Email.assign(:unsubscribe_url, url)
    end
  end

  @doc false
  def send_email(email, config) do
    case config.mailer.deliver(email) do
      {:ok, %{id: id}} -> {:ok, to_string(id)}
      {:ok, _meta} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
end
