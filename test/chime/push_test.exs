defmodule Chime.PushTest do
  use ChimeTest.ConnCase

  import Chime.Test

  alias Chime.Push.Encryption
  alias Mix.Tasks.Chime.Gen.Vapid

  # A browser's subscription: its key pair and auth secret.
  defp browser do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)
    %{public: public, private: private, auth: :crypto.strong_rand_bytes(16)}
  end

  defp b64(bytes), do: Base.url_encode64(bytes, padding: false)

  defp push_config do
    {vapid_public, vapid_private} = :crypto.generate_key(:ecdh, :prime256v1)
    ec = :public_key.generate_key({:namedCurve, :secp256r1})
    p8 = :public_key.pem_encode([:public_key.pem_entry_encode(:ECPrivateKey, ec)])
    rsa = :public_key.generate_key({:rsa, 2048, 65_537})
    rsa_pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPrivateKey, rsa)])

    [
      web: [
        public_key: b64(vapid_public),
        private_key: b64(vapid_private),
        subject: "mailto:ops@app.test"
      ],
      apns: [key: p8, key_id: "KEY123", team_id: "TEAM42", topic: "test.app"],
      fcm: [
        service_account:
          JSON.encode!(%{
            project_id: "app-test",
            client_email: "push@app-test.iam",
            private_key: rsa_pem
          })
      ],
      req_options: [plug: {Req.Test, Chime.Push}]
    ]
  end

  # The inverse of the encryption, as a browser does it.
  defp decrypt(body, browser) do
    <<salt::binary-16, _rs::32, 65, as_public::binary-65, rest::binary>> = body
    ecdh = :crypto.compute_key(:ecdh, as_public, browser.private, :prime256v1)

    hkdf = fn salt, ikm, info, n ->
      binary_part(
        :crypto.mac(:hmac, :sha256, :crypto.mac(:hmac, :sha256, salt, ikm), info <> <<1>>),
        0,
        n
      )
    end

    ikm = hkdf.(browser.auth, ecdh, "WebPush: info" <> <<0>> <> browser.public <> as_public, 32)
    cek = hkdf.(salt, ikm, "Content-Encoding: aes128gcm" <> <<0>>, 16)
    nonce = hkdf.(salt, ikm, "Content-Encoding: nonce" <> <<0>>, 12)
    size = byte_size(rest) - 16
    <<ciphertext::binary-size(size), tag::binary-16>> = rest
    plain = :crypto.crypto_one_time_aead(:aes_128_gcm, cek, nonce, ciphertext, <<>>, tag, false)
    plain |> String.trim_trailing(<<2>>) |> JSON.decode!()
  end

  setup %{conn: conn} do
    {:ok, conn: conn}
  end

  for_each_repo do
    setup ctx do
      reconfigure(ctx, push: push_config())
      Process.put(:pushes, [])
      :ok
    end

    test "a browser's push: encrypted to it, with the app's VAPID token, the link and the tag" do
      ana = person!(1)
      b = browser()

      {:ok, _} =
        Chime.register_device("user:1", %{
          kind: "web",
          token: "https://push.example.com/send/abc",
          keys: %{"p256dh" => b64(b.public), "auth" => b64(b.auth)},
          name: "Firefox"
        })

      test = self()

      Req.Test.stub(Chime.Push, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:web, conn, body})
        Plug.Conn.send_resp(conn, 201, "")
      end)

      {:ok, _} = Chime.notify(ChimeTest.Pushed, %{text: "Hi"}, to: ana)
      assert [%Delivery{status: "sent", ref: "1 of 1 devices"}] = deliver(channel: :push)

      assert_received {:web, conn, body}
      assert conn.host == "push.example.com"
      # Req's test adapter takes content-encoding (aes128gcm) off before the
      # stub: the body is the encrypted one all the same.
      assert ["vapid t=" <> _] = Plug.Conn.get_req_header(conn, "authorization")
      assert [topic] = Plug.Conn.get_req_header(conn, "topic")
      assert byte_size(topic) == 32

      push = decrypt(body, b)

      assert %{
               "title" => "New: Hi",
               "body" => "Open it",
               "icon" => "/icon.png",
               "tag" => "pushed:thread"
             } = push

      assert "https://app.test/notifications/mail/open/" <> _ = push["url"]
      assert [%Chime.Device{last_used_at: %DateTime{}}] = Chime.devices("user:1")
    end

    test "an iPhone's push by APNs, and Android's by FCM" do
      ana = person!(1)
      {:ok, _} = Chime.register_device("user:1", %{kind: "apns", token: "a1b2c3"})
      {:ok, _} = Chime.register_device("user:1", %{kind: "fcm", token: "fcm-token"})
      test = self()

      Req.Test.stub(Chime.Push, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {conn.host, conn.request_path, conn, body})

        case conn.host do
          "api.push.apple.com" ->
            conn
            |> Plug.Conn.put_resp_header("apns-id", "apple-1")
            |> Plug.Conn.send_resp(200, "")

          "oauth2.googleapis.com" ->
            Req.Test.json(conn, %{access_token: "ya29.token", expires_in: 3600})

          "fcm.googleapis.com" ->
            Req.Test.json(conn, %{name: "projects/app-test/messages/1"})
        end
      end)

      {:ok, _} = Chime.notify(ChimeTest.Pushed, %{text: "Hi"}, to: ana)
      assert [%Delivery{status: "sent", ref: "2 of 2 devices"}] = deliver(channel: :push)

      assert_received {"api.push.apple.com", "/3/device/a1b2c3", apns, apns_body}
      assert ["bearer " <> _] = Plug.Conn.get_req_header(apns, "authorization")
      assert ["test.app"] = Plug.Conn.get_req_header(apns, "apns-topic")
      assert ["pushed:thread"] = Plug.Conn.get_req_header(apns, "apns-collapse-id")

      assert %{
               "aps" => %{
                 "alert" => %{"title" => "New: Hi", "body" => "Open it"},
                 "thread-id" => "pushed:thread"
               }
             } =
               JSON.decode!(apns_body)

      assert_received {"oauth2.googleapis.com", "/token", _oauth, oauth_body}
      assert oauth_body =~ "grant_type=urn%3Aietf%3Aparams%3Aoauth%3Agrant-type%3Ajwt-bearer"

      assert_received {"fcm.googleapis.com", "/v1/projects/app-test/messages:send", fcm, fcm_body}
      assert ["Bearer ya29.token"] = Plug.Conn.get_req_header(fcm, "authorization")

      assert %{
               "message" => %{
                 "token" => "fcm-token",
                 "notification" => %{"title" => "New: Hi"},
                 "android" => %{
                   "collapse_key" => "pushed:thread",
                   "notification" => %{"tag" => "pushed:thread"}
                 },
                 "webpush" => %{"notification" => %{"tag" => "pushed:thread", "renotify" => true}}
               }
             } = JSON.decode!(fcm_body)
    end

    test "a device a service says is gone is forgotten, and the log says so" do
      ana = person!(1)
      {:ok, _} = Chime.register_device("user:1", %{kind: "apns", token: "gone"})
      {:ok, _} = Chime.register_device("user:1", %{kind: "apns", token: "here"})

      Req.Test.stub(Chime.Push, fn conn ->
        if String.ends_with?(conn.request_path, "/gone"),
          do: Plug.Conn.send_resp(conn, 410, ~s({"reason":"Unregistered"})),
          else: Plug.Conn.send_resp(conn, 200, "")
      end)

      {:ok, _} = Chime.notify(ChimeTest.Pushed, %{text: "Hi"}, to: ana)

      assert [
               %Delivery{
                 status: "sent",
                 ref:
                   "1 of 2 devices; 1 gone, forgotten: the app is no longer on the device (410)"
               }
             ] =
               deliver(channel: :push)

      assert [%Chime.Device{token: "here"}] = Chime.devices("user:1")
    end

    test "no device, or none turned on, is skipped; every device failing is tried again" do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.Pushed, %{text: "Hi"}, to: ana)

      assert [%Delivery{status: "skipped", reason: "the person has no device turned on"}] =
               deliver(channel: :push)

      {:ok, device} = Chime.register_device("user:1", %{kind: "apns", token: "t"})
      {:ok, _} = Chime.update_device("user:1", device.id, enabled: false)
      {:ok, _} = Chime.notify(ChimeTest.Pushed, %{text: "Again"}, to: ana)
      assert [%Delivery{status: "skipped"}] = deliver(channel: :push)

      {:ok, _} = Chime.update_device("user:1", device.id, enabled: true)
      Req.Test.stub(Chime.Push, &Plug.Conn.send_resp(&1, 503, "down"))
      {:ok, _} = Chime.notify(ChimeTest.Pushed, %{text: "Once more"}, to: ana)

      ExUnit.CaptureLog.capture_log(fn ->
        assert [%Delivery{status: "scheduled", reason: "attempt 1: " <> _}] =
                 deliver(channel: :push, last_attempt: false)
      end)
    end

    test "the devices in the JSON API", %{conn: conn} do
      person!(1)
      conn = as(conn, "user:1")
      b = browser()

      assert %{"vapidPublicKey" => key, "services" => services} =
               conn |> get("/api/notifications/push") |> json_response(200)

      assert byte_size(Base.url_decode64!(key, padding: false)) == 65
      assert Enum.sort(services) == ["apns", "fcm", "web"]

      body = %{
        kind: "web",
        token: "https://push.example.com/x",
        keys: %{p256dh: b64(b.public), auth: b64(b.auth)},
        name: "Safari"
      }

      assert %{"device" => %{"id" => id, "kind" => "web", "name" => "Safari", "enabled" => true}} =
               conn
               |> put_req_header("content-type", "application/json")
               |> post("/api/notifications/devices", JSON.encode!(body))
               |> json_response(201)

      assert %{"error" => "invalid_subscription"} =
               conn
               |> put_req_header("content-type", "application/json")
               |> post(
                 "/api/notifications/devices",
                 JSON.encode!(%{kind: "web", token: "https://x", keys: %{}})
               )
               |> json_response(422)

      assert %{"device" => %{"enabled" => false}} =
               conn
               |> put_req_header("content-type", "application/json")
               |> patch("/api/notifications/devices/#{id}", JSON.encode!(%{enabled: false}))
               |> json_response(200)

      assert %{"devices" => [%{"id" => ^id}]} =
               conn |> get("/api/notifications/devices") |> json_response(200)

      assert %{"error" => "not_found"} =
               build_conn()
               |> as("user:2")
               |> delete("/api/notifications/devices/#{id}")
               |> json_response(404)

      assert %{"removed" => true} =
               conn |> delete("/api/notifications/devices/#{id}") |> json_response(200)

      assert Chime.devices("user:1") == []
    end

    test "a token is one device, of whoever registered it last" do
      {:ok, _} = Chime.register_device("user:1", %{kind: "fcm", token: "same"})
      {:ok, _} = Chime.register_device("user:2", %{kind: "fcm", token: "same"})
      assert Chime.devices("user:1") == []
      assert [_] = Chime.devices("user:2")
    end

    test "push is a channel of the preferences" do
      person!(1)
      assert [%{settings: %{"push" => "on"}} | _] = Chime.preferences("user:1")
    end
  end

  test "the config's checks" do
    base = [repo: R, pubsub: P, resolver: ChimeTest.Resolver]

    assert_raise ArgumentError, ~r/needs :web, :apns or :fcm/, fn ->
      Chime.Config.new(base ++ [push: []])
    end

    assert_raise ArgumentError, ~r/VAPID key/, fn ->
      Chime.Config.new(
        base ++ [push: [web: [public_key: "x", private_key: "y", subject: "mailto:a"]]]
      )
    end

    assert_raise ArgumentError, ~r/:apns of :push needs :key/, fn ->
      Chime.Config.new(base ++ [push: [apns: [key_id: "x"]]])
    end

    assert_raise ArgumentError, ~r/has no project_id/, fn ->
      Chime.Config.new(base ++ [push: [fcm: [service_account: "{}"]]])
    end
  end

  test "mix chime.gen.vapid" do
    output = ExUnit.CaptureIO.capture_io(fn -> Vapid.run([]) end)
    [_, public] = Regex.run(~r/public_key:\s+(\S+)/, output)
    assert byte_size(Base.url_decode64!(public, padding: false)) == 65
    _ = Encryption
  end
end
