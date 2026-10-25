defmodule Chime.LiveTest do
  use ChimeTest.ConnCase

  for_each_repo do
    test "nobody has no bell", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/bell")
      refute html =~ "chime-bell"
    end

    test "the bell's dot, the feed, and reading", %{conn: conn} do
      ana = person!(1)
      now = DateTime.utc_now()
      {:ok, _} = comment!(ana, story: "A", now: minutes(-3, now))
      {:ok, _} = comment!(ana, story: "B", now: minutes(-2, now))
      {:ok, _} = comment!(ana, story: "C", now: minutes(-1, now))

      {:ok, view, html} = live(as(conn, "user:1"), "/bell")
      assert html =~ "chime-dot"
      refute html =~ "chime-feed"

      html = view |> element(".chime-bell") |> render_click()
      refute html =~ "chime-dot"
      assert html =~ "Ana commented on C"
      assert html =~ "Ana commented on B"
      refute html =~ "Ana commented on A"
      assert Chime.counts("user:1") == %{unseen: 0, unread: 3}

      assert view |> element(".chime-more") |> render_click() =~ "Ana commented on A"

      [%{id: id} | _] = Chime.feed("user:1")

      assert {:error, {:live_redirect, %{to: "/stories/C"}}} =
               view |> element("#chime-#{id} .chime-item-open") |> render_click()

      assert Chime.counts("user:1") == %{unseen: 0, unread: 2}
    end

    test "a notification reaches the open page, and a read in another tab", %{conn: conn} do
      ana = person!(1)
      {:ok, view, html} = live(as(conn, "user:1"), "/bell")
      refute html =~ "chime-dot"

      {:ok, _} = comment!(ana)
      assert render(view) =~ "chime-dot"

      Chime.mark_seen("user:1")
      refute render(view) =~ "chime-dot"

      # Open, a new one comes and is seen at once.
      view |> element(".chime-bell") |> render_click()
      {:ok, _} = comment!(ana, story: "Kyoto")
      html = render(view)
      assert html =~ "Ana commented on Kyoto"
      refute html =~ "chime-dot"
    end

    test "mark all read, filter, archive", %{conn: conn} do
      ana = person!(1)
      {:ok, _} = comment!(ana, story: "A")
      {:ok, view, _html} = live(as(conn, "user:1"), "/bell")
      view |> element(".chime-bell") |> render_click()

      assert render(view) =~ "chime-unread"
      view |> element(".chime-read-all") |> render_click()
      refute render(view) =~ "chime-unread"

      assert view |> element("button[phx-value-filter=unread]") |> render_click() =~
               "Nothing yet."

      view |> element("button[phx-value-filter=inbox]") |> render_click()
      [%{id: id}] = Chime.feed("user:1")

      assert view |> element("#chime-#{id} .chime-item-archive") |> render_click() =~
               "Nothing yet."
    end

    test "a click under the unread filter still goes to the notification", %{conn: conn} do
      {:ok, _} = comment!(person!(1))
      {:ok, view, _html} = live(as(conn, "user:1"), "/bell")
      view |> element(".chime-bell") |> render_click()
      view |> element("button[phx-value-filter=unread]") |> render_click()
      [%{id: id}] = Chime.feed("user:1")

      assert {:error, {:live_redirect, %{to: "/stories/Tokyo"}}} =
               view |> element("#chime-#{id} .chime-item-open") |> render_click()
    end

    test "the preferences", %{conn: conn} do
      person!(1)
      {:ok, view, html} = live(as(conn, "user:1"), "/settings")
      assert html =~ "On your stories"

      view
      |> element("#prefs-comments-email")
      |> render_change(%{"category" => "comments", "channel" => "email", "setting" => "weekly"})

      assert [%{settings: %{"email" => "weekly"}} | _] = Chime.preferences("user:1")
      assert render(view) =~ ~s(<option value="weekly" selected)
    end
  end
end
