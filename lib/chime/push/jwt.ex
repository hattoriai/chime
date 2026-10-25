defmodule Chime.Push.JWT do
  @moduledoc false
  # The signed tokens of the push services: ES256 for Web Push (VAPID) and
  # APNs, RS256 for Google's OAuth (FCM).

  @doc false
  @spec es256(map(), map(), binary()) :: String.t()
  def es256(header, claims, private_key) do
    input = encode(header) <> "." <> encode(claims)
    der = :crypto.sign(:ecdsa, :sha256, input, [private_key, :prime256v1])
    input <> "." <> b64(raw_signature(der))
  end

  @doc false
  @spec rs256(map(), map(), String.t()) :: String.t()
  def rs256(header, claims, pem) do
    input = encode(header) <> "." <> encode(claims)
    [entry | _] = :public_key.pem_decode(pem)
    key = :public_key.pem_entry_decode(entry)
    input <> "." <> b64(:public_key.sign(input, :sha256, key))
  end

  @doc false
  # The raw private key of a PEM of an EC key (APNs' .p8, a PKCS #8).
  @spec ec_private_key(String.t()) :: binary()
  def ec_private_key(pem) do
    [entry | _] = :public_key.pem_decode(pem)

    case :public_key.pem_entry_decode(entry) do
      {:ECPrivateKey, _version, private, _params, _public, _attrs} -> private
      {:ECPrivateKey, _version, private, _params, _public} -> private
    end
  end

  @doc false
  def b64(bytes), do: Base.url_encode64(bytes, padding: false)

  defp encode(map), do: map |> JSON.encode!() |> b64()

  # An ECDSA signature in DER, as the 64 bytes of r and s of a JWT.
  defp raw_signature(der) do
    {:"ECDSA-Sig-Value", r, s} = :public_key.der_decode(:"ECDSA-Sig-Value", der)
    pad(:binary.encode_unsigned(r)) <> pad(:binary.encode_unsigned(s))
  end

  defp pad(bytes) when byte_size(bytes) < 32, do: pad(<<0>> <> bytes)
  defp pad(bytes), do: bytes
end
