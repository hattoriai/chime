defmodule Chime.AudienceTest do
  use ChimeTest.DataCase

  import Chime.Test

  defp users!(repo, n, attrs \\ []) do
    rows = for i <- 1..n, do: Map.merge(%{name: "U#{i}", confirmed: true}, Map.new(attrs))
    {_, users} = repo.insert_all(ChimeTest.UserRow, rows, returning: [:id])
    Enum.map(users, & &1.id)
  end

  for_each_repo do
    test "everyone of the app's query, a page at a time, in jobs", %{repo: repo} do
      ids = users!(repo, 2_345)
      users!(repo, 3, confirmed: false)

      assert {:ok, %Event{status: "sending", recipients: 0} = event} =
               Chime.notify(ChimeTest.Announcement, %{"title" => "We moved"})

      assert [%Oban.Job{args: %{"job" => "audience", "cursor" => nil}}] = repo.all(Oban.Job)
      assert repo.aggregate(Notification, :count) == 0

      # The first page, as its job.
      assert :ok =
               Chime.Worker.perform(%Oban.Job{
                 args: %{"job" => "audience", "id" => event.id, "cursor" => nil}
               })

      assert repo.aggregate(Notification, :count) == 1_000

      assert %Event{status: "sending", cursor: cursor, recipients: 1_000} =
               repo.get!(Event, event.id)

      assert cursor == JSON.encode!(Enum.at(Enum.sort(ids), 999))

      # Its job again does nothing.
      assert :ok = Chime.Notify.page(Chime.Config.get(), event.id, nil)
      assert repo.aggregate(Notification, :count) == 1_000

      run_audiences()
      assert repo.aggregate(Notification, :count) == 2_345
      assert %Event{status: "sent", recipients: 2_345} = repo.get!(Event, event.id)
      assert [%{title: "We moved"}] = feed("user:#{List.last(ids)}")
      assert Chime.counts("user:#{hd(ids)}") == %{unseen: 1, unread: 1}
    end

    test "the actor is left out, and the event's data picks the query", %{repo: repo} do
      [a, _b] = users!(repo, 2, confirmed: false)
      users!(repo, 5)

      {:ok, event} =
        Chime.notify(ChimeTest.Announcement, %{
          "title" => "x",
          "only" => "unconfirmed",
          "by" => "user:#{a}"
        })

      run_audiences()
      assert %Event{recipients: 1} = repo.get!(Event, event.id)
      assert feed("user:#{a}") == []
    end

    test "an audience at a time", %{repo: repo} do
      [id] = users!(repo, 1)

      {:ok, %Event{status: "scheduled"}} =
        Chime.notify(ChimeTest.Announcement, %{"title" => "Later"}, at: minutes(5))

      run_scheduled(minutes(6))
      run_audiences()
      assert [%{title: "Later"}] = feed("user:#{id}")
    end

    test "cancelled while it is sent: no more pages", %{repo: repo} do
      users!(repo, 1_500)
      {:ok, event} = Chime.notify(ChimeTest.Announcement, %{"title" => "Oops"}, key: "a:1")
      Chime.Notify.page(Chime.Config.get(), event.id, nil)
      assert {:ok, _} = Chime.cancel("a:1", feed: :remove)
      run_audiences()
      assert %Event{status: "cancelled"} = repo.get!(Event, event.id)
      assert repo.aggregate(Notification, :count) == 0
    end

    test ":to over the audience", %{repo: repo} do
      users!(repo, 3)

      {:ok, %Event{status: "sent", recipients: 1}} =
        Chime.notify(ChimeTest.Announcement, %{"title" => "x"}, to: "user:1")
    end
  end
end
