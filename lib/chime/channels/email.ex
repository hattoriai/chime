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
      need `:unsubscribe_url` and `:secret_key_base` in the config.

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
    config = Config.get()

    case message.notifier.email(message.data, message.recipient, message.notification) do
      %{__struct__: Swoosh.Email} = email ->
        email
        |> address(config, message)
        |> unsubscribe(config, message, message.category)
        |> send_email(config)

      other ->
        raise ArgumentError,
              "#{inspect(message.notifier)}.email/3 must return a Swoosh.Email, got: #{inspect(other)}"
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
