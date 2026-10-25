defmodule Chime.Push.FCM do
  @moduledoc false
  # A push by Firebase Cloud Messaging (HTTP v1): an access token of the
  # app's service account, kept until near its end, and the message to a
  # device's token, with the group as the notification's tag, so that a
  # new one replaces the one before on the device.

  alias Chime.Push.JWT

  @compile {:no_warn_undefined, [Req]}

  @scope "https://www.googleapis.com/auth/firebase.messaging"

  @doc false
  @spec send(Chime.Device.t(), map(), map()) ::
          :ok | {:ok, String.t()} | {:gone, String.t()} | {:error, term()}
  def send(device, payload, fcm) do
    with {:ok, access} <- access_token(fcm) do
      url = "https://fcm.googleapis.com/v1/projects/#{fcm.project_id}/messages:send"

      case Req.post(
             url,
             [json: %{message: message(device, payload)}, auth: {:bearer, access}, retry: false] ++
               fcm.req_options
           ) do
        {:ok, %{status: 200, body: %{"name" => name}}} ->
          {:ok, name}

        {:ok, %{status: status, body: body}} when status in [400, 404] ->
          refused(status, body)

        {:ok, %{status: status, body: body}} ->
          {:error, {status, body}}

        {:error, error} ->
          {:error, error}
      end
    end
  end

  defp message(device, payload) do
    notification =
      %{title: payload.title} |> put(:body, payload[:body]) |> put(:image, payload[:image])

    %{
      token: device.token,
      notification: notification,
      # FCM's data is of strings.
      data: %{} |> put(:url, payload[:url]) |> put(:id, payload[:id]),
      android:
        %{notification: %{} |> put(:tag, payload[:tag]) |> put(:icon, payload[:icon])}
        |> put(:collapse_key, payload[:tag]),
      webpush: %{
        notification:
          %{}
          |> put(:icon, payload[:icon])
          |> put(:badge, payload[:badge])
          |> put(:tag, payload[:tag])
          |> put(:renotify, payload[:tag] && true),
        fcm_options: %{} |> put(:link, payload[:url])
      }
    }
  end

  defp refused(status, body) do
    if unregistered?(body),
      do: {:gone, "FCM: the token is no longer registered (#{status})"},
      else: {:error, {status, body}}
  end

  defp unregistered?(%{"error" => %{"details" => details}}) when is_list(details) do
    Enum.any?(details, &(&1["errorCode"] in ["UNREGISTERED", "INVALID_ARGUMENT"]))
  end

  defp unregistered?(%{"error" => %{"status" => "NOT_FOUND"}}), do: true
  defp unregistered?(_body), do: false

  # The access token of the service account, kept until a minute before
  # its end.
  defp access_token(fcm) do
    key = {__MODULE__, fcm.client_email}
    now = System.os_time(:second)

    case :persistent_term.get(key, nil) do
      {token, until} when now < until ->
        {:ok, token}

      _ ->
        claims = %{
          iss: fcm.client_email,
          scope: @scope,
          aud: fcm.token_uri,
          iat: now,
          exp: now + 3600
        }

        assertion = JWT.rs256(%{alg: "RS256", typ: "JWT"}, claims, fcm.private_key)

        form = [grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: assertion]

        case Req.post(fcm.token_uri, [form: form, retry: false] ++ fcm.req_options) do
          {:ok, %{status: 200, body: %{"access_token" => token, "expires_in" => seconds}}} ->
            :persistent_term.put(key, {token, now + seconds - 60})
            {:ok, token}

          {:ok, %{status: status, body: body}} ->
            {:error, {:oauth, status, body}}

          {:error, error} ->
            {:error, error}
        end
    end
  end

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
