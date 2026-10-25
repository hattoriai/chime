defmodule Chime.Push.WebPush do
  @moduledoc false
  # A browser's push: the message encrypted to its subscription (RFC 8291),
  # with a VAPID token of the app's keys (RFC 8292), posted to its endpoint.

  alias Chime.Push.{Encryption, JWT}

  @compile {:no_warn_undefined, [Req]}

  @doc false
  @spec send(Chime.Device.t(), map(), map()) :: :ok | {:gone, String.t()} | {:error, term()}
  def send(device, payload, web) do
    body =
      payload
      |> JSON.encode!()
      |> Encryption.encrypt(decode(device.keys["p256dh"]), decode(device.keys["auth"]))

    headers = [
      {"authorization", "vapid t=#{vapid(device.token, web)}, k=#{web.public_key}"},
      {"content-encoding", "aes128gcm"},
      {"content-type", "application/octet-stream"},
      {"ttl", to_string(web.ttl)},
      {"urgency", "normal"}
    ]

    # A newer message of the same tag replaces the one not yet shown.
    headers = if payload[:tag], do: [{"topic", topic(payload.tag)} | headers], else: headers

    case Req.post(device.token, [body: body, headers: headers, retry: false] ++ web.req_options) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status}} when status in [404, 410] ->
        {:gone, "the browser's subscription is gone (#{status})"}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  # The VAPID token of an endpoint's origin, for 12 hours.
  defp vapid(endpoint, web) do
    %URI{scheme: scheme, host: host, port: port} = URI.parse(endpoint)
    origin = "#{scheme}://#{host}" <> if(port in [443, 80, nil], do: "", else: ":#{port}")
    claims = %{aud: origin, exp: System.os_time(:second) + 12 * 3600, sub: web.subject}
    JWT.es256(%{typ: "JWT", alg: "ES256"}, claims, web.private_key)
  end

  # A topic is up to 32 characters of the URL-safe alphabet.
  defp topic(tag), do: :crypto.hash(:sha256, tag) |> JWT.b64() |> binary_part(0, 32)

  defp decode(text), do: Base.url_decode64!(text, padding: false)
end
