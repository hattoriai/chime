# Channels

A channel is a way to tell a person. Chime has two: the feed and email.
Your app adds its own.

## The feed

The bell and its list in your app: `deliver :feed`. A notification is in
the feed at once, unless the person turned the feed off for its
category. Its `feed/2` says what it shows: `:title`, and `:body`, `:url`
and `:icon`, and anything else, which the JSON API gives as `extra`.

## Email

`deliver :email`, with the config's `:mailer` (a `Swoosh.Mailer`) and
`:email_from`. The notifier's `email/3` gives the subject and the body,
as a `Swoosh.Email`; Chime gives it:

* `To:`, the person's address and name (a person with no address is
  skipped, and the log says so);
* `From:`, the config's, unless the email has one;
* unless it is required, the headers of one-click unsubscribe (RFC 8058),
  `List-Unsubscribe` and `List-Unsubscribe-Post`, which Gmail and Yahoo
  ask of a sender of many emails, and the same address in the email's
  assigns as `:unsubscribe_url`, for its footer.

The mailer's id of the email is kept as the delivery's `ref`.

A notifier's email in your app's templates:

```elixir
def email(data, recipient, notification) do
  Swoosh.Email.new(subject: "#{Chime.actors(notification)} commented on #{data["story"]}")
  |> Swoosh.Email.html_body(
    MyAppWeb.Emails.new_comment(
      data: data,
      recipient: recipient,
      unsubscribe_url: Chime.unsubscribe_url(recipient, notification)
    )
  )
end
```

## Your own

Telegram, SMS, Slack, Discord, your own push: a module of
`Chime.Channel`, named in the config.

```elixir
{Chime, ..., channels: [telegram: {MyApp.Chime.Telegram, token: System.fetch_env!("TELEGRAM_TOKEN")}]}
```

```elixir
defmodule MyApp.Chime.Telegram do
  @behaviour Chime.Channel

  @impl true
  def deliver(%Chime.Message{} = message, opts) do
    case message.recipient.data.telegram_chat do
      nil ->
        {:skip, "the person has no Telegram chat"}

      chat ->
        text = Chime.Message.render(message)

        case MyApp.Telegram.send(opts[:token], chat, text) do
          {:ok, %{"message_id" => id}} -> {:ok, to_string(id)}
          {:error, :blocked} -> {:skip, "the person blocked the bot"}
          {:error, reason} -> {:error, reason}
        end
    end
  end
end
```

`deliver/2` gets the `Chime.Message`: the notification, the person as
the resolver gives them now, the notifier's data, and whether it is
required. `Chime.Message.render/1` calls the notifier's function of the
channel's name, `telegram(data, recipient, notification)`, when it has
one, else gives what the feed shows.

It answers:

* `{:ok, ref}` or `:ok` - sent; `ref` is kept;
* `{:skip, reason}` - not sent, on purpose: not tried again, and the
  reason goes in the log;
* `{:error, reason}` - failed: Oban tries again with its backoff, five
  attempts in all, and the delivery is `"failed"` after the last.

Whether it goes at all (the preferences, `:if`, `:unless`) is decided
before `deliver/2` is called.

A channel is in the preferences too: a person can turn it off for a
category, as the feed and email.

## When it goes

Each delivery is an Oban job at its time, of the worker Chime.Worker,
given to Oban in the transaction of the notification, so that both are
kept or neither is. Give Chime the queue (`oban: [name: Oban, queue:
:notifications]`) and run it:

```elixir
config :my_app, Oban, queues: [default: 10, notifications: 20]
```

A delivery is decided and sent once: a second job of it, or a retry
after it was sent, does nothing.
