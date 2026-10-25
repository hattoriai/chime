defmodule Chime.Push.Encryption do
  @moduledoc false
  # The encryption of a Web Push message (RFC 8291, "aes128gcm" of RFC
  # 8188): an ephemeral key of the server's and the browser's key agree
  # on a secret, mixed with the subscription's auth secret, that gives the
  # content key and nonce of one record.

  @record_size 4096

  @doc false
  # The body of a message to a subscription's p256dh key and auth secret.
  # `ephemeral` and `salt` are for the tests of the RFC's example.
  @spec encrypt(binary(), binary(), binary(), keyword()) :: binary()
  def encrypt(plaintext, ua_public, auth_secret, opts \\ []) do
    {as_public, as_private} =
      Keyword.get_lazy(opts, :ephemeral, fn -> :crypto.generate_key(:ecdh, :prime256v1) end)

    salt = Keyword.get_lazy(opts, :salt, fn -> :crypto.strong_rand_bytes(16) end)

    ecdh_secret = :crypto.compute_key(:ecdh, ua_public, as_private, :prime256v1)
    key_info = "WebPush: info" <> <<0>> <> ua_public <> as_public
    ikm = hkdf(auth_secret, ecdh_secret, key_info, 32)

    cek = hkdf(salt, ikm, "Content-Encoding: aes128gcm" <> <<0>>, 16)
    nonce = hkdf(salt, ikm, "Content-Encoding: nonce" <> <<0>>, 12)

    # One record, the last: the content and its delimiter, 2.
    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, plaintext <> <<2>>, <<>>, true)

    salt <>
      <<@record_size::unsigned-big-32, byte_size(as_public)::8>> <> as_public <> ciphertext <> tag
  end

  # HKDF with SHA-256, of one block (RFC 5869).
  defp hkdf(salt, ikm, info, length) do
    prk = :crypto.mac(:hmac, :sha256, salt, ikm)
    binary_part(:crypto.mac(:hmac, :sha256, prk, info <> <<1>>), 0, length)
  end
end
