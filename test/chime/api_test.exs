defmodule Chime.APITest do
  use ChimeTest.ConnCase

  for_each_repo do
    test "a request with no person is a 401", %{conn: conn} do
      assert %{"error" => "unauthorized"} =
               conn |> get("/api/notifications") |> json_response(401)
    end

    test "the feed, its counts and pages", %{conn: conn} do
      ana = person!(1)
      now = DateTime.utc_now()
      {:ok, _} = comment!(ana, story: "A", now: minutes(-3, now))
      {:ok, _} = comment!(ana, story: "B", now: minutes(-2, now))
      {:ok, _} = comment!(ana, story: "C", now: minutes(-1, now))
      conn = as(conn, "user:1")

      assert %{"notifications" => [c, b], "more" => true, "unseen" => 3, "unread" => 3} =
               conn |> get("/api/notifications?limit=2") |> json_response(200)

      assert %{
               "title" => "Ana commented on C",
               "url" => "/stories/C",
               "count" => 1,
               "read" => false,
               "kind" => "new_comment"
             } = c

      assert %{"actors" => [%{"name" => "Ana"}], "insertedAt" => "20" <> _} = c

      assert %{"notifications" => [%{"title" => "Ana commented on A"}], "more" => false} =
               conn |> get("/api/notifications?limit=2&before=#{b["id"]}") |> json_response(200)

      assert %{"unseen" => 0, "unread" => 3} =
               conn |> post("/api/notifications/seen") |> json_response(200)

      assert %{"unseen" => 0, "unread" => 2} =
               conn |> post("/api/notifications/#{c["id"]}/read") |> json_response(200)

      assert %{"notifications" => [_, _]} =
               conn |> get("/api/notifications?filter=unread") |> json_response(200)

      assert %{"unread" => 1} =
               conn |> post("/api/notifications/#{b["id"]}/archive") |> json_response(200)

      assert %{"notifications" => [%{"archived" => true}]} =
               conn |> get("/api/notifications?filter=archived") |> json_response(200)

      assert %{"unread" => 2} =
               conn |> post("/api/notifications/#{b["id"]}/unarchive") |> json_response(200)

      assert %{"unread" => 3} =
               conn |> post("/api/notifications/#{c["id"]}/unread") |> json_response(200)

      assert %{"unread" => 0} = conn |> post("/api/notifications/read") |> json_response(200)

      assert %{"unseen" => 0, "unread" => 0} =
               conn |> get("/api/notifications/counts") |> json_response(200)
    end

    test "another person's notification is not found", %{conn: conn} do
      {:ok, _} = comment!(person!(1))
      [%{id: id}] = Chime.Test.feed("user:1")

      assert %{"error" => "not_found"} =
               conn |> as("user:2") |> post("/api/notifications/#{id}/read") |> json_response(404)

      assert %{"error" => "not_found"} =
               conn |> as("user:2") |> post("/api/notifications/nope/read") |> json_response(404)

      assert %{unread: 1} = Chime.counts("user:1")
    end

    test "the preferences, and their changes", %{conn: conn} do
      conn = as(conn, "user:1")

      assert %{"categories" => [comments, _, billing], "channels" => channels} =
               conn |> get("/api/notifications/preferences") |> json_response(200)

      assert %{
               "key" => "comments",
               "label" => "Comments",
               "required" => false,
               "settings" => %{"email" => "on"}
             } = comments

      assert %{"key" => "billing", "required" => true} = billing
      assert %{"key" => "email", "settings" => ["on", "daily", "weekly", "off"]} in channels

      assert %{"categories" => [%{"settings" => %{"email" => "daily", "feed" => "off"}} | _]} =
               conn
               |> put_req_header("content-type", "application/json")
               |> put(
                 "/api/notifications/preferences",
                 JSON.encode!(%{preferences: %{comments: %{email: "daily", feed: "off"}}})
               )
               |> json_response(200)

      assert %{"error" => "required", "category" => "billing", "channel" => "email"} =
               conn
               |> put_req_header("content-type", "application/json")
               |> put(
                 "/api/notifications/preferences",
                 JSON.encode!(%{
                   preferences: %{comments: %{email: "weekly"}, billing: %{email: "off"}}
                 })
               )
               |> json_response(422)

      # Nothing of a refused change is kept.
      assert [%{settings: %{"email" => "daily"}} | _] = Chime.preferences("user:1")
    end

    test "a token of Chime's, as a bearer or in the query", %{conn: conn} do
      {:ok, _} = comment!(person!(1))

      assert %{"token" => token, "expiresIn" => 86_400} =
               conn |> as("user:1") |> post("/api/notifications/token") |> json_response(200)

      assert %{"unread" => 1} =
               build_conn()
               |> put_req_header("authorization", "Bearer " <> token)
               |> get("/api/notifications/counts")
               |> json_response(200)

      assert %{"unread" => 1} =
               build_conn()
               |> get("/api/notifications/counts?token=#{token}")
               |> json_response(200)

      assert %{"error" => "unauthorized"} =
               build_conn()
               |> put_req_header("authorization", "Bearer nope")
               |> get("/api/notifications/counts")
               |> json_response(401)
    end

    test "the stream: the counts, then the news", %{conn: conn} do
      ana = person!(1)
      test = self()

      task =
        Task.async(fn ->
          conn = conn |> as("user:1") |> get("/api/notifications/stream")
          send(test, :done)
          conn
        end)

      Process.sleep(100)
      {:ok, _} = comment!(ana)
      Process.sleep(50)
      Chime.mark_seen("user:1")
      Process.sleep(50)
      send(task.pid, {Chime.API, :close})
      conn = Task.await(task)

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["text/event-stream"]

      assert [
               {"counts", %{"unseen" => 0, "unread" => 0}},
               {"notified", %{"unseen" => 1, "unread" => 1}},
               {"updated", %{"unseen" => 0, "unread" => 1}}
             ] = events(conn.resp_body)
    end
  end

  defp events(body) do
    for "event: " <> event <- String.split(body, "\n\n", trim: true) do
      [name, "data: " <> data] = String.split(event, "\n")
      {name, JSON.decode!(data)}
    end
  end
end
