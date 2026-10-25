defmodule Chime.Channels.Slack do
  @moduledoc """
  Slack: a message to a person, or to a channel of the team's.

      channels: [slack: {Chime.Channels.Slack, token: System.fetch_env!("SLACK_BOT_TOKEN")}]

  With a bot's `:token`, Chime posts with `chat.postMessage` to the
  person's Slack id (or a channel's), from the recipient's data
  (`data.slack`, or `to: {:data, :slack_id}`), or to one `to:
  "#alerts"` for everyone. Without a token, the address is an incoming
  webhook's URL (`to: "https://hooks.slack.com/services/..."`, or each
  person's in their data).

  It says the notifier's `slack/3` when it has one (a text, or a map of
  `:title`, `:body`, `:url`), else the feed's words, with the link that
  reads the notification. Options: `:token`, `:to`, `:req_options`.
  """

  @behaviour Chime.Channel

  alias Chime.Channels.HTTP

  @impl Chime.Channel
  def deliver(message, opts) do
    case HTTP.address(message, opts) do
      nil -> {:skip, "the person has no #{message.channel} address"}
      address -> send_to(address, HTTP.words(message), opts)
    end
  end

  defp send_to(address, words, opts) do
    case opts[:token] do
      nil ->
        address |> HTTP.post([json: %{text: text(words)}], opts) |> HTTP.result("Slack")

      token ->
        "https://slack.com/api/chat.postMessage"
        |> HTTP.post(
          [
            json: %{channel: address, text: text(words), unfurl_links: false},
            auth: {:bearer, token}
          ],
          opts
        )
        |> api_result()
    end
  end

  # Slack's mrkdwn: the title bold, linked when there is a link.
  defp text(%{url: nil} = words),
    do: Enum.join(Enum.reject(["*#{words.title}*", words.body], &is_nil/1), "\n")

  defp text(words),
    do: Enum.join(Enum.reject(["*<#{words.url}|#{words.title}>*", words.body], &is_nil/1), "\n")

  defp api_result({:ok, %{status: 200, body: %{"ok" => true, "ts" => ts}}}), do: {:ok, ts}
  defp api_result({:ok, %{status: 200, body: %{"ok" => true}}}), do: :ok

  defp api_result({:ok, %{status: 200, body: %{"ok" => false, "error" => error}}})
       when error in ~w(channel_not_found user_not_found is_archived not_in_channel account_inactive invalid_auth),
       do: {:skip, "Slack: #{error}"}

  defp api_result({:ok, %{body: %{"error" => error}}}), do: {:error, error}
  defp api_result(other), do: HTTP.result(other, "Slack")
end
