defmodule Chime.Channels.Webhook do
  @moduledoc """
  A webhook: the notification as JSON, signed, posted to an address of
  the app's or the person's.

      channels: [webhook: {Chime.Channels.Webhook, to: "https://hooks.myapp.com/chime", secret: System.fetch_env!("CHIME_WEBHOOK_SECRET")}]

  The address is one for everyone (`to:`), or each person's in their data
  (`data.webhook`). The body:

      {
        "id": "<the delivery's notification>",
        "kind": "new_comment", "category": "comments", "workspace": null,
        "recipient": "user:42",
        "title": "...", "body": "...", "url": "<the link that reads it>",
        "data": {...}, "count": 1, "actors": [...],
        "at": "2026-10-25T14:02:11Z"
      }

  With `:secret`, the `x-chime-signature` header is `t=<unix time>,v1=<the
  HMAC-SHA256, in hex, of "<t>.<body>">`: the receiver checks it, and that
  the time is recent. A 4xx is skipped; a 5xx or no answer is tried again.
  Options: `:to`, `:secret`, `:req_options`.
  """

  @behaviour Chime.Channel

  alias Chime.Channels.HTTP

  @impl Chime.Channel
  def deliver(message, opts) do
    case HTTP.address(message, opts) do
      nil -> {:skip, "the person has no #{message.channel} address"}
      url -> post(url, message, opts)
    end
  end

  defp post(url, message, opts) do
    n = message.notification
    words = HTTP.words(message)

    body =
      JSON.encode!(%{
        id: n.id,
        kind: message.kind,
        category: message.category,
        workspace: n.workspace,
        recipient: message.recipient.id,
        title: words.title,
        body: words.body,
        url: words.url,
        data: message.data,
        count: n.count,
        actors: n.actors,
        at: DateTime.utc_now()
      })

    headers = [{"content-type", "application/json"} | signature(body, opts[:secret])]
    url |> HTTP.post([body: body, headers: headers], opts) |> HTTP.result("The webhook")
  end

  defp signature(_body, nil), do: []

  defp signature(body, secret) do
    t = System.os_time(:second)
    mac = :crypto.mac(:hmac, :sha256, secret, "#{t}.#{body}") |> Base.encode16(case: :lower)
    [{"x-chime-signature", "t=#{t},v1=#{mac}"}]
  end
end
