defmodule Chime.MessagesTest do
  use ChimeTest.ConnCase

  import Chime.Test

  test "the template has every word of Chime's, and only them" do
    {:ok, po} = Expo.PO.parse_file(Path.expand("../../priv/gettext/chime.pot", __DIR__))

    template =
      MapSet.new(po.messages, fn
        %Expo.Message.Singular{msgid: id} ->
          Enum.join(id)

        %Expo.Message.Plural{msgid: id, msgid_plural: plural} ->
          {Enum.join(id), Enum.join(plural)}
      end)

    source =
      for file <- Path.wildcard(Path.expand("../../lib/**/*.ex", __DIR__)),
          text = File.read!(file),
          word <- words(text),
          into: MapSet.new(),
          do: word

    assert MapSet.difference(source, template) |> MapSet.to_list() == []
    assert MapSet.difference(template, source) |> MapSet.to_list() == []
  end

  defp words(text) do
    plurals =
      for [_, one, many] <-
            Regex.scan(~r/\btn\(\s*"((?:[^"\\]|\\.)+)",\s*"((?:[^"\\]|\\.)+)"/, text),
          do: {one, many}

    singles = for [_, one] <- Regex.scan(~r/(?<![\w.])t\(\s*"((?:[^"\\]|\\.)+)"/, text), do: one
    plurals ++ singles
  end

  for_each_repo do
    test "English without a Gettext" do
      assert Chime.actors(%Chime.Notification{
               actors: [%{"name" => "Ana"}, %{"name" => "Rui"}],
               actor_count: 2
             }) ==
               "Ana and Rui"

      assert Chime.actors(%Chime.Notification{actors: [%{"name" => "Ana"}], actor_count: 2}) ==
               "Ana and 1 other"
    end

    test "the app's languages, by its Gettext", ctx do
      reconfigure(ctx, gettext: ChimeTest.Gettext)
      Gettext.put_locale(ChimeTest.Gettext, "pt")

      assert Chime.actors(%Chime.Notification{
               actors: [%{"name" => "Ana"}, %{"name" => "Rui"}],
               actor_count: 2
             }) ==
               "Ana e Rui"

      assert Chime.actors(%Chime.Notification{actors: [%{"name" => "Ana"}], actor_count: 5}) ==
               "Ana e mais 4"

      assert Chime.actors(%Chime.Notification{actors: []}) == "Alguém"
      # A word not translated is English.
      assert Chime.Messages.t("Show more") == "Show more"
    end

    test "the bell, the feed and the preferences in the request's language",
         %{conn: conn} = ctx do
      reconfigure(ctx, gettext: ChimeTest.Gettext)
      person!(1)
      conn = conn |> as("user:1") |> Plug.Conn.put_session("locale", "pt")
      Gettext.put_locale(ChimeTest.Gettext, "pt")

      {:ok, view, html} = live(conn, "/bell")
      assert html =~ ~s(aria-label="Notificações")
      assert view |> element(".chime-bell") |> render_click() =~ "Ainda nada."

      {:ok, _view, html} = live(conn, "/settings")
      assert html =~ "Comentários"
      assert html =~ "Semanal"
    end

    test "a digest in the person's language", ctx do
      reconfigure(ctx, gettext: ChimeTest.Gettext)
      Gettext.put_locale(ChimeTest.Gettext, "en")
      ana = person!(1, locale: "pt")
      now = ~U[2026-10-25 12:00:00.000000Z]
      {:ok, _} = Chime.notify(ChimeTest.Followed, %{"name" => "Rui"}, to: ana, now: now)
      deliver(at: now)
      run_digests(~U[2026-10-26 10:00:00Z])

      assert_email_sent(subject: "As suas notificações da semana")
      assert Gettext.get_locale(ChimeTest.Gettext) == "en"
    end

    test "the page to unsubscribe in the person's language", %{conn: conn} = ctx do
      reconfigure(ctx, gettext: ChimeTest.Gettext)
      person!(1, locale: "pt")
      "https://app.test" <> path = Chime.unsubscribe_url("user:1", "comments")

      html = conn |> get(path) |> html_response(200)
      assert html =~ "Deixar de receber emails de The app sobre comentários?"
      assert html =~ "Cancelar subscrição"
    end
  end
end
