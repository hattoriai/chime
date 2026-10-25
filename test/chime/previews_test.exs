defmodule Chime.PreviewsTest do
  use ChimeTest.ConnCase

  defp admin(conn), do: Phoenix.ConnTest.init_test_session(conn, %{"admin" => true})

  test "the notifiers with previews, from the app's modules" do
    notifiers = Chime.Preview.notifiers(:chime)
    assert ChimeTest.NewComment in notifiers
    assert ChimeTest.Invited in notifiers
    refute ChimeTest.Followed in notifiers
  end

  test "what each channel says, alone and as a group" do
    preview =
      Chime.Preview.render(ChimeTest.NewComment, %{story: "Tokyo", text: "Lovely.", author: "Ana"})

    assert %{title: "Ana commented on Tokyo", body: "Lovely."} = preview.feed
    assert %{title: "Ana and 2 others commented on Tokyo"} = preview.group
    assert %Swoosh.Email{subject: "Ana commented on Tokyo"} = preview.email
    assert [{"telegram", "New comment on Tokyo"}] = preview.others
  end

  for_each_repo do
    test "the pages", %{conn: conn} do
      {:ok, _view, html} = live(admin(conn), "/admin/notifications/previews")
      assert html =~ "ChimeTest.NewComment"

      {:ok, view, html} = live(admin(conn), "/admin/notifications/previews/ChimeTest.NewComment")
      assert html =~ "Ana commented on Tokyo"
      assert html =~ "Ana and 2 others commented on Tokyo"
      assert html =~ "New comment on Tokyo"

      assert view |> element("a", "A long one") |> render_click() =~ "Rui commented on Kyoto"

      {:ok, _view, html} = live(admin(conn), "/admin/notifications/previews/ChimeTest.Invited")
      assert html =~ "You are invited to Kyoto"
      assert html =~ "Accept"
      assert html =~ "<iframe"

      assert_raise Chime.Admin.NotFound, fn ->
        live(admin(conn), "/admin/notifications/previews/Nope")
      end
    end
  end
end
