defmodule Chime.HTTPChannelsTest do
  use ChimeTest.DataCase

  import Chime.Test

  @req [req_options: [plug: {Req.Test, Chime.Channels}]]

  defp channels(slack_opts \\ []) do
    [
      slack: {Chime.Channels.Slack, @req ++ slack_opts},
      discord: {Chime.Channels.Discord, @req},
      teams: {Chime.Channels.Teams, @req ++ [to: "https://teams.example.com/hook"]},
      webhook:
        {Chime.Channels.Webhook, @req ++ [to: "https://hooks.app.test/chime", secret: "shh"]},
      sms:
        {Chime.Channels.Twilio,
         @req ++ [account_sid: "AC1", auth_token: "tok", from: "+15550000000"]}
    ]
  end

  defp person_everywhere!(n) do
    user = person!(n)
    recipient = ChimeTest.Resolver.recipient(user)

    ChimeTest.People.put(%{
      recipient
      | data: %{
          slack: "U#{n}",
          discord: "https://discord.com/api/webhooks/#{n}/x",
          phone: "+35191234567#{n}"
        }
    })

    recipient
  end

  defp stub do
    test = self()

    Req.Test.stub(Chime.Channels, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test, {conn.host, conn.request_path, conn, body})

      case conn.host do
        "slack.com" -> Req.Test.json(conn, %{ok: true, ts: "1700.1"})
        "api.twilio.com" -> conn |> Plug.Conn.put_status(201) |> Req.Test.json(%{sid: "SM1"})
        _ -> Plug.Conn.send_resp(conn, 204, "")
      end
    end)
  end

  for_each_repo do
    test "Slack, Discord, Teams, a webhook and SMS", ctx do
      reconfigure(ctx, channels: channels(token: "xoxb-1"))
      ana = person_everywhere!(1)
      stub()

      {:ok, _} = Chime.notify(ChimeTest.Everywhere, %{text: "Hi"}, to: ana)
      sent = deliver() |> Map.new(&{&1.channel, &1})

      assert %{status: "sent", ref: "1700.1"} = sent["slack"]
      assert %{status: "sent"} = sent["discord"]
      assert %{status: "sent"} = sent["teams"]
      assert %{status: "sent"} = sent["webhook"]
      assert %{status: "sent", ref: "SM1"} = sent["sms"]

      assert_received {"slack.com", "/api/chat.postMessage", slack, slack_body}
      assert ["Bearer xoxb-1"] = Plug.Conn.get_req_header(slack, "authorization")

      assert %{"channel" => "U1", "text" => "*<https://app.test/notifications/mail/open/" <> _} =
               JSON.decode!(slack_body)

      assert_received {"discord.com", "/api/webhooks/1/x", _, discord_body}

      assert %{
               "embeds" => [
                 %{"title" => "Hi", "description" => "More", "url" => "https://app.test/" <> _}
               ]
             } =
               JSON.decode!(discord_body)

      assert_received {"teams.example.com", "/hook", _, teams_body}

      assert %{
               "attachments" => [
                 %{
                   "content" => %{
                     "type" => "AdaptiveCard",
                     "body" => [%{"text" => "Hi"} | _],
                     "actions" => [%{"type" => "Action.OpenUrl"}]
                   }
                 }
               ]
             } =
               JSON.decode!(teams_body)

      assert_received {"hooks.app.test", "/chime", hook, hook_body}
      assert ["t=" <> signed] = Plug.Conn.get_req_header(hook, "x-chime-signature")
      [t, "v1=" <> mac] = String.split(signed, ",")

      assert mac ==
               :crypto.mac(:hmac, :sha256, "shh", "#{t}.#{hook_body}")
               |> Base.encode16(case: :lower)

      assert %{
               "kind" => "everywhere",
               "recipient" => "user:1",
               "title" => "Hi",
               "data" => %{"text" => "Hi"}
             } = JSON.decode!(hook_body)

      assert_received {"api.twilio.com", "/2010-04-01/Accounts/AC1/Messages.json", twilio,
                       twilio_body}

      assert ["Basic " <> auth] = Plug.Conn.get_req_header(twilio, "authorization")
      assert Base.decode64!(auth) == "AC1:tok"

      assert %{"To" => "+351912345671", "From" => "+15550000000", "Body" => "SMS: Hi"} =
               URI.decode_query(twilio_body)
    end

    test "Slack by an incoming webhook, with no token", ctx do
      reconfigure(ctx,
        channels: [
          slack: {Chime.Channels.Slack, @req ++ [to: "https://hooks.slack.com/services/T/B/X"]}
        ]
      )

      stub()

      {:ok, _} = Chime.notify(ChimeTest.OnlySlack, %{}, to: person!(1))
      assert [%Delivery{status: "sent"}] = deliver()
      assert_received {"hooks.slack.com", "/services/T/B/X", _, body}
      assert %{"text" => "*Deploy done*"} = JSON.decode!(body)
    end

    test "no address, a refusal for good, and a failure to try again", ctx do
      reconfigure(ctx, channels: channels(token: "xoxb-1"))
      ana = person!(1)

      Req.Test.stub(Chime.Channels, fn conn ->
        case conn.host do
          "hooks.app.test" -> Plug.Conn.send_resp(conn, 500, "oops")
          "teams.example.com" -> Plug.Conn.send_resp(conn, 410, "gone")
        end
      end)

      {:ok, _} = Chime.notify(ChimeTest.Everywhere, %{text: "Hi"}, to: ana)

      ExUnit.CaptureLog.capture_log(fn ->
        sent = deliver(last_attempt: false) |> Map.new(&{&1.channel, &1})
        assert %{status: "skipped", reason: "the person has no slack address"} = sent["slack"]
        assert %{status: "skipped", reason: "the person has no phone number"} = sent["sms"]
        assert %{status: "skipped", reason: "Teams refused it (410)"} = sent["teams"]
        assert %{status: "scheduled", reason: "attempt 1: " <> _} = sent["webhook"]
      end)
    end

    test "Slack's and Twilio's refusals of an address", ctx do
      reconfigure(ctx, channels: channels(token: "xoxb-1"))
      ana = person_everywhere!(1)

      Req.Test.stub(Chime.Channels, fn conn ->
        case conn.host do
          "slack.com" -> Req.Test.json(conn, %{ok: false, error: "user_not_found"})
          "api.twilio.com" -> conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{code: 21_610})
          _ -> Plug.Conn.send_resp(conn, 204, "")
        end
      end)

      {:ok, _} = Chime.notify(ChimeTest.Everywhere, %{text: "Hi"}, to: ana)
      sent = deliver() |> Map.new(&{&1.channel, &1})
      assert %{status: "skipped", reason: "Slack: user_not_found"} = sent["slack"]
      assert %{status: "skipped", reason: "Twilio: the person replied STOP"} = sent["sms"]
    end
  end
end
