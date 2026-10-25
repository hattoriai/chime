defmodule Chime.Channel do
  @moduledoc ~S"""
  A way to tell a person, besides the feed and email: Telegram, SMS,
  Slack, Discord, the app's own push. The app writes a module and names
  it in the config's `:channels`:

      {Chime, ..., channels: [telegram: {MyApp.Chime.Telegram, token: "..."}]}

      defmodule MyApp.Chime.Telegram do
        @behaviour Chime.Channel

        @impl true
        def deliver(%Chime.Message{} = message, opts) do
          case message.recipient.data do
            %{telegram_chat: nil} ->
              {:skip, "the person has no Telegram chat"}

            %{telegram_chat: chat} ->
              %{title: title} = Chime.Message.render(message)

              case Telegram.send(opts[:token], chat, title) do
                {:ok, %{"message_id" => id}} -> {:ok, to_string(id)}
                {:error, :blocked} -> {:skip, "the person blocked the bot"}
                {:error, reason} -> {:error, reason}
              end
          end
        end
      end

  and a notifier delivers by it: `deliver :telegram`.

  `c:deliver/2` gets the `Chime.Message` (the notification, the person,
  the notifier's data) and the options of the config, and answers:

    * `{:ok, ref}` or `:ok` - sent; `ref`, a string, is kept (the
      service's id of it);
    * `{:skip, reason}` - not sent, on purpose, and not tried again: the
      reason goes in the log (`Chime.Explain`);
    * `{:error, reason}` - failed: Oban tries again, with its backoff, and
      the delivery is `"failed"` after the last attempt.

  Whether it goes at all (the person's preferences, `:if`, `:unless`) is
  decided before `c:deliver/2` is called.
  """

  @doc "Sends a notification to a person."
  @callback deliver(Chime.Message.t(), opts :: keyword()) ::
              :ok | {:ok, String.t() | nil} | {:skip, String.t()} | {:error, term()}
end
