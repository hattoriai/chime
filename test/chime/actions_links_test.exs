defmodule Chime.ActionsLinksTest do
  use ChimeTest.ConnCase

  import Chime.Test

  for_each_repo do
    test "an action: the notifier takes it, the notification keeps it and is read" do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.Invited, %{team: "Kyoto"}, to: ana)
      [%{id: id, actions: [%{key: "accept", label: "Accept"}, %{key: "decline"}]}] = feed(ana)

      assert {:ok, %{action: "accept", url: "/teams/Kyoto"}} = Chime.act("user:1", id, "accept")

      assert [%{action: "accept", read: true, title: "You accepted Kyoto", actions: []}] =
               feed(ana)

      assert {:error, :already} = Chime.act("user:1", id, "decline")
      assert explain(id) =~ ~r/feed\s+action\s+accept/
    end

    test "what an action refuses" do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.Invited, %{team: "full"}, to: ana)
      [%{id: id}] = feed(ana)

      assert {:error, :team_full} = Chime.act("user:1", id, "accept")
      assert [%{action: nil, read: false}] = feed(ana)
      assert {:error, :unknown_action} = Chime.act("user:1", id, "explode")
      assert {:error, :not_found} = Chime.act("user:2", id, "decline")
      assert {:error, :not_found} = Chime.act("user:1", "nope", "decline")
    end

    test "actions in the JSON API", %{conn: conn} do
      {:ok, _} = Chime.notify(ChimeTest.Invited, %{team: "Kyoto"}, to: person!(1))
      conn = as(conn, "user:1")

      %{"notifications" => [%{"id" => id, "actions" => [%{"key" => "accept"}, _]}]} =
        conn |> get("/api/notifications") |> json_response(200)

      assert %{"action" => "decline", "url" => nil, "unread" => 0} =
               conn |> post("/api/notifications/#{id}/actions/decline") |> json_response(200)

      assert %{"error" => "already"} =
               conn |> post("/api/notifications/#{id}/actions/accept") |> json_response(422)
    end

    test "actions in LiveView", %{conn: conn} do
      {:ok, _} = Chime.notify(ChimeTest.Invited, %{team: "Kyoto"}, to: person!(1))
      {:ok, view, _html} = live(as(conn, "user:1"), "/bell")
      html = view |> element(".chime-bell") |> render_click()
      assert html =~ "chime-action"

      assert {:error, {:live_redirect, %{to: "/teams/Kyoto"}}} =
               view |> element(~s(.chime-action[data-action="accept"])) |> render_click()
    end

    test "a link of an email reads the notification, then goes on", %{conn: conn} do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.Invited, %{team: "Kyoto"}, to: ana)
      deliver(channel: :email)

      assert_email_sent(fn email ->
        [_, url] = Regex.run(~r/href="([^"]+)"/, email.html_body)
        "https://app.test" <> path = url
        assert "https://app.test/notifications/mail/open/" <> _ = email.assigns.link
        Process.put(:link, path)
        true
      end)

      Chime.subscribe("user:1")
      conn = get(conn, Process.get(:link))
      assert redirected_to(conn, 302) == "https://app.test/teams/Kyoto"
      assert [%{read: true, seen: true, clickedAt: %DateTime{}}] = feed(ana)
      assert_receive {Chime, :updated, %{unread: 0}}

      [n] = Chime.feed("user:1")
      assert explain(n) =~ ~r/link\s+opened/
    end

    test "a forged link is a 404, and Chime.link without :mail_url is the address",
         %{conn: conn} = ctx do
      assert conn |> get("/notifications/mail/open/nope") |> response(404)

      reconfigure(ctx, mail_url: nil)

      assert Chime.link(%Notification{id: Ecto.UUID.generate(), recipient: "user:1"}, "/x") ==
               "https://app.test/x"
    end
  end
end
