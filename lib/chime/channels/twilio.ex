defmodule Chime.Channels.Twilio do
  @moduledoc """
  SMS by Twilio: a text to the person's phone.

      channels: [
        sms:
          {Chime.Channels.Twilio,
           account_sid: System.fetch_env!("TWILIO_ACCOUNT_SID"),
           auth_token: System.fetch_env!("TWILIO_AUTH_TOKEN"),
           from: "+15551234567"}
      ]

  The phone is the recipient's data (`data.phone`, or `to: {:data,
  :mobile}`), in E.164 (`"+351912345678"`). `:messaging_service_sid` sends
  from a Messaging Service instead of `:from`. It says the notifier's
  function of the channel's name (`sms/3`, a text) when it has one, else
  the feed's title and the link that reads the notification. A number
  Twilio refuses for good (not a mobile, or the person replied STOP) is
  skipped, with its reason. Options: `:account_sid`, `:auth_token`,
  `:from`, `:messaging_service_sid`, `:to`, `:req_options`.
  """

  @behaviour Chime.Channel

  alias Chime.Channels.HTTP

  # Twilio's errors of a number that will not take the text.
  @gone %{
    21_211 => "the number is not valid",
    21_610 => "the person replied STOP",
    21_612 => "Twilio cannot reach the number",
    21_614 => "the number is not a mobile"
  }

  @impl Chime.Channel
  def deliver(message, opts) do
    case HTTP.address(message, Keyword.put_new(opts, :to, {:data, :phone})) do
      nil -> {:skip, "the person has no phone number"}
      phone -> send_text(phone, message, opts)
    end
  end

  defp send_text(phone, message, opts) do
    words = HTTP.words(message)
    text = Enum.join(Enum.reject([words.title, words.url], &is_nil/1), " ")
    sid = Keyword.fetch!(opts, :account_sid)

    from =
      case opts[:messaging_service_sid] do
        nil -> [From: Keyword.fetch!(opts, :from)]
        service -> [MessagingServiceSid: service]
      end

    "https://api.twilio.com/2010-04-01/Accounts/#{sid}/Messages.json"
    |> HTTP.post(
      [
        form: [To: phone, Body: text] ++ from,
        auth: {:basic, "#{sid}:#{Keyword.fetch!(opts, :auth_token)}"}
      ],
      opts
    )
    |> result()
  end

  defp result({:ok, %{status: 201, body: %{"sid" => sid}}}), do: {:ok, sid}

  defp result({:ok, %{status: 400, body: %{"code" => code}}}) when is_map_key(@gone, code),
    do: {:skip, "Twilio: " <> Map.fetch!(@gone, code)}

  defp result(other), do: HTTP.result(other, "Twilio")
end
