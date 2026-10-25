defmodule Chime.Channels.Teams do
  @moduledoc """
  Microsoft Teams: an Adaptive Card by a channel's workflow webhook (or
  an incoming webhook).

      channels: [teams: {Chime.Channels.Teams, to: System.fetch_env!("TEAMS_WEBHOOK_URL")}]

  The address is the webhook's URL: one for everyone (`to:`), or each
  person's in their data (`data.teams`). It says the notifier's `teams/3`
  (a text, or `:title`, `:body`, `:url`), else the feed's words, with a
  button to the link that reads the notification. Options: `:to`,
  `:req_options`.
  """

  @behaviour Chime.Channel

  alias Chime.Channels.HTTP

  @impl Chime.Channel
  def deliver(message, opts) do
    case HTTP.address(message, opts) do
      nil -> {:skip, "the person has no #{message.channel} address"}
      url -> url |> HTTP.post([json: card(HTTP.words(message))], opts) |> HTTP.result("Teams")
    end
  end

  defp card(words) do
    body =
      [%{type: "TextBlock", text: words.title, weight: "Bolder", size: "Medium", wrap: true}] ++
        if(words.body, do: [%{type: "TextBlock", text: words.body, wrap: true}], else: [])

    actions =
      if words.url, do: [%{type: "Action.OpenUrl", title: "Open", url: words.url}], else: []

    %{
      type: "message",
      attachments: [
        %{
          contentType: "application/vnd.microsoft.card.adaptive",
          content: %{
            "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
            type: "AdaptiveCard",
            version: "1.4",
            body: body,
            actions: actions
          }
        }
      ]
    }
  end
end
