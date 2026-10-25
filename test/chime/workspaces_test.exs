defmodule Chime.WorkspacesTest do
  use ChimeTest.ConnCase

  import Chime.Test

  defp comment_in!(workspace, to, opts \\ []) do
    Chime.notify(
      ChimeTest.NewComment,
      %{
        to: List.wrap(to),
        story: Keyword.get(opts, :story, "Tokyo"),
        text: "x",
        author: Keyword.get(opts, :author, "Ana")
      },
      workspace: workspace
    )
  end

  for_each_repo do
    test "a notification of a workspace, its feed and its counts" do
      ana = person!(1)
      {:ok, %Event{workspace: "team:1"}} = comment_in!("team:1", ana, story: "A")
      {:ok, _} = comment_in!("team:2", ana, story: "B")
      {:ok, _} = comment!(ana, story: "C")

      assert [
               %{title: "Ana commented on C"},
               %{title: "Ana commented on B"},
               %{title: "Ana commented on A"}
             ] =
               feed(ana)

      assert [%{title: "Ana commented on A"}] = feed(ana, workspace: "team:1")
      assert Chime.counts("user:1") == %{unseen: 3, unread: 3}
      assert Chime.counts("user:1", workspace: "team:1") == %{unseen: 1, unread: 1}
      assert Chime.counts("user:1", workspace: "team:3") == %{unseen: 0, unread: 0}

      assert %{unseen: 0, unread: 1} = Chime.mark_seen("user:1", workspace: "team:1")
      assert Chime.counts("user:1") == %{unseen: 2, unread: 3}
      assert Chime.counts("user:1", workspace: "team:2") == %{unseen: 1, unread: 1}

      assert %{unread: 0} = Chime.mark_read("user:1", :all, workspace: "team:2")
      assert Chime.counts("user:1", workspace: "team:2") == %{unseen: 0, unread: 0}
      assert Chime.counts("user:1") == %{unseen: 1, unread: 2}
    end

    test "groups are a workspace's own" do
      ana = person!(1)
      {:ok, _} = comment_in!("team:1", ana, author: "Rui")
      {:ok, _} = comment_in!("team:2", ana, author: "Kenji")
      {:ok, _} = comment_in!("team:1", ana, author: "Mei")

      assert [%{count: 2}] = feed(ana, workspace: "team:1")
      assert [%{count: 1}] = feed(ana, workspace: "team:2")
    end

    test "the notifier's workspace/1, and :workspace over it" do
      {:ok, %Event{workspace: "team:7"}} =
        Chime.notify(ChimeTest.InTeam, %{team: 7}, to: "user:1")

      {:ok, %Event{workspace: "team:9"}} =
        Chime.notify(ChimeTest.InTeam, %{team: 7}, to: "user:1", workspace: "team:9")

      {:ok, %Event{workspace: nil}} =
        Chime.notify(ChimeTest.InTeam, %{team: 7}, to: "user:1", workspace: nil)
    end

    test "a workspace's own preferences, over the person's for all" do
      ana = person!(1)
      :ok = Chime.put_preference("user:1", :comments, :email, :off)
      :ok = Chime.put_preference("user:1", :comments, :email, :on, workspace: "team:1")

      assert [%{settings: %{"email" => "on"}} | _] =
               Chime.preferences("user:1", workspace: "team:1")

      assert [%{settings: %{"email" => "off"}} | _] =
               Chime.preferences("user:1", workspace: "team:2")

      assert [%{settings: %{"email" => "off"}} | _] = Chime.preferences("user:1")

      {:ok, _} = comment_in!("team:1", ana)
      {:ok, _} = comment_in!("team:2", ana, story: "Kyoto")
      {:ok, _} = comment!(ana, story: "Osaka")

      assert %{"Tokyo" => "sent", "Kyoto" => "skipped", "Osaka" => "skipped"} =
               deliver(at: minutes(11), channel: :email)
               |> Enum.map(fn d ->
                 {Chime.explain(d.notification_id).notification.event.data["story"], d.status}
               end)
               |> Map.new()
               |> Map.merge(
                 for d <- deliveries(ana, channel: :email), d.status == "skipped", into: %{} do
                   {Chime.explain(d.notification_id).notification.event.data["story"], "skipped"}
                 end
               )
    end

    test "a link to unsubscribe turns the category's email off in every workspace" do
      person!(1)
      :ok = Chime.put_preference("user:1", :comments, :email, :on, workspace: "team:1")
      :ok = Chime.Preferences.unsubscribe(Chime.Config.get(), "user:1", "comments")

      assert [%{settings: %{"email" => "off"}} | _] =
               Chime.preferences("user:1", workspace: "team:1")
    end

    test "the log says the workspace" do
      {:ok, _} = comment_in!("team:1", person!(1))
      [n] = Chime.feed("user:1")
      assert explain(n) =~ "(comments, in team:1)"
    end

    test "the bell and the feed of the page's workspace", %{conn: conn} do
      ana = person!(1)
      {:ok, _} = comment_in!("team:1", ana, story: "A")
      {:ok, _} = comment_in!("team:2", ana, story: "B")
      conn = conn |> as("user:1") |> Plug.Conn.put_session("workspace", "team:1")

      {:ok, view, _html} = live(conn, "/bell")
      html = view |> element(".chime-bell") |> render_click()
      assert html =~ "Ana commented on A"
      refute html =~ "Ana commented on B"
      assert Chime.counts("user:1", workspace: "team:2") == %{unseen: 1, unread: 1}

      # A notification of another workspace leaves the page's dot as it is.
      view |> element(".chime-bell") |> render_click()
      {:ok, _} = comment_in!("team:2", ana, story: "C")
      refute render(view) =~ "chime-dot"
      {:ok, _} = comment_in!("team:1", ana, story: "D")
      assert render(view) =~ "chime-dot"
    end

    test "the JSON API of a workspace", %{conn: conn} do
      ana = person!(1)
      {:ok, _} = comment_in!("team:1", ana, story: "A")
      {:ok, _} = comment_in!("team:2", ana, story: "B")
      conn = as(conn, "user:1")

      assert %{"notifications" => [%{"title" => "Ana commented on B"}], "unread" => 1} =
               conn |> get("/api/notifications?workspace=team:2") |> json_response(200)

      assert %{"unread" => 2} = conn |> get("/api/notifications/counts") |> json_response(200)

      assert %{"unread" => 1, "unseen" => 0} =
               conn
               |> Plug.Conn.put_session("workspace", "team:1")
               |> post("/api/notifications/seen")
               |> json_response(200)

      assert Chime.counts("user:1") == %{unseen: 1, unread: 2}

      assert %{"categories" => [%{"settings" => %{"email" => "daily"}} | _]} =
               conn
               |> put_req_header("content-type", "application/json")
               |> put(
                 "/api/notifications/preferences?workspace=team:1",
                 JSON.encode!(%{preferences: %{comments: %{email: "daily"}}})
               )
               |> json_response(200)

      assert [%{settings: %{"email" => "on"}} | _] = Chime.preferences("user:1")
    end
  end
end
