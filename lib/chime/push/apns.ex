defmodule Chime.Push.APNs do
  @moduledoc false
  # An Apple device's push: a JSON payload posted over HTTP/2 to APNs,
  # with a token of the app's .p8 key, made again every 50 minutes.

  alias Chime.Push.JWT

  @compile {:no_warn_undefined, [Req]}

  @hosts %{
    production: "https://api.push.apple.com",
    sandbox: "https://api.sandbox.push.apple.com"
  }

  @doc false
  @spec send(Chime.Device.t(), map(), map()) ::
          :ok | {:ok, String.t()} | {:gone, String.t()} | {:error, term()}
  def send(device, payload, apns) do
    alert = Map.reject(%{title: payload.title, body: payload[:body]}, fn {_k, v} -> is_nil(v) end)

    aps =
      %{alert: alert, sound: "default"}
      |> put(:badge, payload[:badge])
      |> put(:"thread-id", payload[:tag])
      |> put(:"mutable-content", payload[:image] && 1)

    body =
      %{aps: aps}
      |> put(:url, payload[:url])
      |> put(:image, payload[:image])
      |> put(:id, payload[:id])

    headers =
      [
        {"authorization", "bearer " <> token(apns)},
        {"apns-topic", apns.topic},
        {"apns-push-type", "alert"},
        {"apns-priority", "10"}
      ]
      |> then(
        &if(payload[:tag], do: [{"apns-collapse-id", collapse_id(payload.tag)} | &1], else: &1)
      )

    url = Map.fetch!(@hosts, apns.env) <> "/3/device/" <> device.token

    options =
      [json: body, headers: headers, retry: false, connect_options: [protocols: [:http2]]] ++
        apns.req_options

    case Req.post(url, options) do
      {:ok, %{status: 200} = response} ->
        {:ok, response |> Req.Response.get_header("apns-id") |> List.first()}

      {:ok, %{status: 410}} ->
        {:gone, "the app is no longer on the device (410)"}

      {:ok, %{status: 400, body: %{"reason" => reason}}}
      when reason in ["BadDeviceToken", "DeviceTokenNotForTopic"] ->
        {:gone, "APNs: #{reason}"}

      {:ok, %{status: status, body: body}} ->
        {:error, {status, body}}

      {:error, error} ->
        {:error, error}
    end
  end

  # The provider token, kept for 50 minutes (APNs takes one of up to an hour).
  defp token(apns) do
    key = {__MODULE__, apns.key_id}
    now = System.os_time(:second)

    case :persistent_term.get(key, nil) do
      {token, at} when now - at < 3000 ->
        token

      _ ->
        token =
          JWT.es256(
            %{alg: "ES256", kid: apns.key_id},
            %{iss: apns.team_id, iat: now},
            JWT.ec_private_key(apns.key)
          )

        :persistent_term.put(key, {token, now})
        token
    end
  end

  # A collapse id is up to 64 bytes.
  defp collapse_id(tag) when byte_size(tag) <= 64, do: tag
  defp collapse_id(tag), do: :crypto.hash(:sha256, tag) |> Base.encode16(case: :lower)

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
