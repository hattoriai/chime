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

      refute Map.has_key?(JSON.decode!(apns_body)["aps"], "mutable-content")

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

    test "a push for a phone's app: its category, its level and its data" do
      ana = person!(1)
      b = browser()
      {:ok, _} = Chime.register_device("user:1", %{kind: "apns", token: "a1b2c3"})
      {:ok, _} = Chime.register_device("user:1", %{kind: "fcm", token: "fcm-token"})

      {:ok, _} =
        Chime.register_device("user:1", %{
          kind: "web",
          token: "https://push.example.com/send/abc",
          keys: %{"p256dh" => b64(b.public), "auth" => b64(b.auth)}
        })

      test = self()

      Req.Test.stub(Chime.Push, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {conn.host, conn, body})

        case conn.host do
          "oauth2.googleapis.com" -> Req.Test.json(conn, %{access_token: "t", expires_in: 3600})
          "fcm.googleapis.com" -> Req.Test.json(conn, %{name: "projects/app-test/messages/1"})
          _ -> Plug.Conn.send_resp(conn, 200, "")
        end
      end)

      {:ok, _} =
        Chime.notify(ChimeTest.Actionable, %{category: "report", level: :time_sensitive}, to: ana)

      assert [%Delivery{status: "sent", ref: "3 of 3 devices"}] = deliver(channel: :push)

      assert_received {"api.push.apple.com", _apns, apns_body}
      apns = JSON.decode!(apns_body)

      assert %{
               "category" => "report",
               "interruption-level" => "time-sensitive",
               # The app's notification service extension runs.
               "mutable-content" => 1
             } = apns["aps"]

      # The app's data at the top, and Chime's id, not the app's.
      assert %{"report_id" => 7, "dogs" => ["Kai", "Luna"]} = apns
      assert {:ok, _} = Ecto.UUID.cast(apns["id"])

      assert_received {"fcm.googleapis.com", _fcm, fcm_body}

      assert %{"category" => "report", "report_id" => "7", "dogs" => ~s(["Kai","Luna"])} =
               JSON.decode!(fcm_body)["message"]["data"]

      assert_received {"push.example.com", web, web_body}
      assert ["high"] = Plug.Conn.get_req_header(web, "urgency")

      assert %{
               "category" => "report",
               "interruption_level" => "time-sensitive",
               "data" => %{"report_id" => 7}
             } = decrypt(web_body, b)
    end

    test "without a category or an image, an APNs push is not mutable; a passive one is low" do
      ana = person!(1)
      b = browser()
      {:ok, _} = Chime.register_device("user:1", %{kind: "apns", token: "a1b2c3"})

      {:ok, _} =
        Chime.register_device("user:1", %{
          kind: "web",
          token: "https://push.example.com/send/abc",
          keys: %{"p256dh" => b64(b.public), "auth" => b64(b.auth)}
        })

      test = self()

      Req.Test.stub(Chime.Push, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {conn.host, conn, body})
        Plug.Conn.send_resp(conn, 200, "")
      end)

      {:ok, _} = Chime.notify(ChimeTest.Actionable, %{level: "passive"}, to: ana)
      assert [%Delivery{status: "sent"}] = deliver(channel: :push)

      assert_received {"api.push.apple.com", _apns, apns_body}
      aps = JSON.decode!(apns_body)["aps"]
      assert aps["interruption-level"] == "passive"
      refute Map.has_key?(aps, "category")
      refute Map.has_key?(aps, "mutable-content")

      assert_received {"push.example.com", web, _body}
      assert ["low"] = Plug.Conn.get_req_header(web, "urgency")

      {:ok, _} = Chime.notify(ChimeTest.Actionable, %{image: "https://cdn.test/a.jpg"}, to: ana)
      assert [%Delivery{status: "sent"}] = deliver(channel: :push)
      assert_received {"api.push.apple.com", _apns, apns_body}
      aps = JSON.decode!(apns_body)["aps"]
      assert aps["mutable-content"] == 1
      refute Map.has_key?(aps, "interruption-level")
      assert_received {"push.example.com", web, _body}
      assert ["normal"] = Plug.Conn.get_req_header(web, "urgency")
    end

    test "a push's interruption level is one of Apple's" do
      ana = person!(1)
      {:ok, _} = Chime.register_device("user:1", %{kind: "apns", token: "a1b2c3"})
      {:ok, _} = Chime.notify(ChimeTest.Actionable, %{level: "loud"}, to: ana)

      assert_raise ArgumentError, ~r/:interruption_level of a push is :passive/, fn ->
        deliver(channel: :push)
      end
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

    test "without :push in the config, deliver :push is skipped, and nothing raises", ctx do
      reconfigure(ctx, push: nil)
      ana = person!(1)

      assert {:ok, _} = Chime.notify(ChimeTest.Pushed, %{text: "Hi"}, to: ana)
      assert deliver(channel: :push) == []
      assert [_] = Chime.feed("user:1")
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

    test "a Live Activity: updated, then ended, with its own push type and topic" do
      test = self()

      Req.Test.stub(Chime.Push, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test, {:apns, conn, JSON.decode!(body)})

        conn
        |> Plug.Conn.put_resp_header("apns-id", "apple-9")
        |> Plug.Conn.send_resp(200, "")
      end)

      assert {:ok, "apple-9"} =
               Chime.LiveActivity.update("act-1", %{"dogs" => 3},
                 stale_date: ~U[2026-11-11 10:30:00Z],
                 alert: %{title: "Ana is here"},
                 timestamp: ~U[2026-11-11 10:00:00Z]
               )

      assert_received {:apns, conn, body}
      assert conn.request_path == "/3/device/act-1"
      assert ["bearer " <> _] = Plug.Conn.get_req_header(conn, "authorization")
      assert ["liveactivity"] = Plug.Conn.get_req_header(conn, "apns-push-type")
      assert ["test.app.push-type.liveactivity"] = Plug.Conn.get_req_header(conn, "apns-topic")
      assert ["10"] = Plug.Conn.get_req_header(conn, "apns-priority")

      assert body == %{
               "aps" => %{
                 "event" => "update",
                 "timestamp" => 1_794_391_200,
                 "content-state" => %{"dogs" => 3},
                 "stale-date" => 1_794_393_000,
                 "alert" => %{"title" => "Ana is here"}
               }
             }

      assert {:ok, _} =
               Chime.LiveActivity.finish("act-1", %{"dogs" => 0},
                 dismissal_date: ~U[2026-11-11 10:00:00Z],
                 priority: :low
               )

      assert_received {:apns, conn, %{"aps" => aps}}
      assert ["5"] = Plug.Conn.get_req_header(conn, "apns-priority")
      assert %{"event" => "end", "dismissal-date" => 1_794_391_200} = aps
      refute Map.has_key?(aps, "alert")
    end

    test "a Live Activity APNs no longer knows is gone" do
      Req.Test.stub(Chime.Push, &Plug.Conn.send_resp(&1, 410, ""))
      assert {:gone, _} = Chime.LiveActivity.finish("over", %{})
    end

    test "a Live Activity needs :apns", ctx do
      reconfigure(ctx, push: Keyword.take(push_config(), [:web, :req_options]))
      assert {:error, :no_apns} = Chime.LiveActivity.update("act-1", %{})
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
