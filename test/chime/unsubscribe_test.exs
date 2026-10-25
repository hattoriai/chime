defmodule Chime.UnsubscribeTest do
  use ChimeTest.ConnCase

  for_each_repo do
    test "the link asks first, then a post unsubscribes, with no session", %{conn: conn} do
      person!(1)
      "https://app.test" <> path = Chime.unsubscribe_url("user:1", "comments")

      html = conn |> get(path) |> html_response(200)
      assert html =~ "Stop the emails of The app about comments?"
      assert [%{settings: %{"email" => "on"}} | _] = Chime.preferences("user:1")

      html =
        build_conn()
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> post(path, "List-Unsubscribe=One-Click")
        |> html_response(200)

      assert html =~ "You will no longer get emails of The app about comments."
      assert [%{settings: %{"email" => "off"}} | _] = Chime.preferences("user:1")
    end

    test "a forged link is a 404", %{conn: conn} do
      assert conn |> get("/notifications/unsubscribe/nope") |> html_response(404) =~ "not valid"
      assert build_conn() |> post("/notifications/unsubscribe/nope") |> html_response(404)
    end
  end
end
