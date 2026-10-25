defmodule Chime.Push.EncryptionTest do
  use ExUnit.Case, async: true

  alias Chime.Push.Encryption

  defp b64(text), do: Base.url_decode64!(text, padding: false)

  # The example of RFC 8291, section 5.
  test "the RFC's example" do
    body =
      Encryption.encrypt(
        "When I grow up, I want to be a watermelon",
        b64(
          "BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4"
        ),
        b64("BTBZMqHH6r4Tts7J_aSIgg"),
        ephemeral:
          {b64(
             "BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8"
           ), b64("yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw")},
        salt: b64("DGv6ra1nlYgDCS1FRnbzlw")
      )

    assert Base.url_encode64(body, padding: false) ==
             "DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPTpK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN"
  end
end
