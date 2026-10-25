defmodule Chime.AdminTest do
  use ChimeTest.ConnCase

  import Chime.Test

  defp admin(conn), do: Phoenix.ConnTest.init_test_session(conn, %{"admin" => true})

  for_each_repo do
    test "nobody but the access's admins: a 404", %{conn: conn} do
      assert_error_sent 404, fn -> get(conn, "/admin/notifications") end
      assert_error_sent 404, fn -> get(as(conn, "user:1"), "/admin/notifications") end
    end

    test "the first page: the last day, the failed, the events", %{conn: conn} do
      ana = person!(1, telegram: "fails")
      {:ok, _} = comment!(ana, key: "c:1")

      ExUnit.CaptureLog.capture_log(fn -> deliver(channel: :telegram) end)

      {:ok, view, html} = live(admin(conn), "/admin/notifications")
      assert html =~ "new_comment"
      assert html =~ "c:1"
      assert has_element?(view, ~s(.tile[data-status="failed"] b), "1")

      [failed] = deliveries(ana, channel: :telegram)
      assert view |> element("#failed-#{failed.id} button") |> render_click() =~ "Sent again."

      assert [%Delivery{status: "scheduled", attempts: 0, reason: "sent again"}] =
               deliveries(ana, channel: :telegram)
    end

    test "a person's page, from the search", %{conn: conn} do
      ana = person!(1)
      {:ok, _} = comment!(ana)
      Chime.register_device("user:1", %{kind: "fcm", token: "t", name: "Pixel"})

      {:ok, view, _html} = live(admin(conn), "/admin/notifications")

      assert {:error, {:live_redirect, %{to: "/admin/notifications/people/user%3A1"}}} =
               render_patch(view, "/admin/notifications?person=user:1")

      {:ok, _view, html} = live(admin(conn), "/admin/notifications/people/user:1")
      assert html =~ "new_comment"
      assert html =~ "Pixel"
      assert html =~ "Comments"
    end

    test "a notification's page: its log, its data, sending again", %{conn: conn} do
      ana = person!(1)
      {:ok, _} = comment!(ana)
      [n] = Chime.feed("user:1")
      [email] = deliveries(ana, channel: :email)
      Chime.mark_read("user:1", [n.id])
      deliver(at: minutes(11), channel: :email)

      {:ok, view, html} = live(admin(conn), "/admin/notifications/notifications/#{n.id}")
      assert html =~ "Ana commented on Tokyo"
      assert html =~ "read in the feed at"
      assert html =~ "Lovely."

      assert view |> element("#d-#{email.id} button") |> render_click() =~ "Sent again."
      assert [%Delivery{status: "scheduled"}] = deliveries(ana, channel: :email)
    end

    test "resend refuses what waits, and what is not" do
      ana = person!(1)
      {:ok, _} = comment!(ana)
      [d] = deliveries(ana, channel: :email)
      assert {:error, :waiting} = Chime.resend(d.id)
      assert {:error, :not_found} = Chime.resend(Ecto.UUID.generate())
      assert {:error, :not_found} = Chime.resend("nope")
    end
  end
end
