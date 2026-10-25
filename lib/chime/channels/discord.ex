defmodule Chime.Channels.Discord do
  @moduledoc """
  Discord: a message by a channel's webhook.

      channels: [discord: {Chime.Channels.Discord, to: System.fetch_env!("DISCORD_WEBHOOK_URL")}]

  The address is a webhook's URL: one for everyone (`to:`), or each
  person's in their data (`data.discord`). It says the notifier's
  `discord/3` (a text, or `:title`, `:body`, `:url`), else the feed's
  words, as an embed with the link that reads the notification. A webhook
  Discord says is gone is skipped. Options: `:to`, `:username`,
  `:req_options`.
  """

  @behaviour Chime.Channel

  alias Chime.Channels.HTTP

  @impl Chime.Channel
  def deliver(message, opts) do
    case HTTP.address(message, opts) do
      nil ->
        {:skip, "the person has no #{message.channel} address"}

      url ->
        words = HTTP.words(message)
        embed = %{title: words.title} |> put(:description, words.body) |> put(:url, words.url)
        body = %{embeds: [embed]} |> put(:username, opts[:username])
        url |> HTTP.post([json: body], opts) |> HTTP.result("Discord")
    end
  end

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
