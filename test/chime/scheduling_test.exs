defmodule Chime.SchedulingTest do
  use ChimeTest.DataCase

  import Chime.Test

  for_each_repo do
    test "a notification at a time: nothing now, everything then", %{repo: repo} do
      ana = person!(1)
      at = minutes(60)

      {:ok, %Event{status: "scheduled", scheduled_at: ^at, recipients: 1} = event} =
        comment!(ana, at: at, key: "c:1")

      assert feed(ana) == []
      assert [%Oban.Job{args: %{"job" => "notify"}, scheduled_at: ^at}] = repo.all(Oban.Job)

      run_scheduled(minutes(30))
      assert feed(ana) == []

      run_scheduled(minutes(61))
      assert [%{title: "Ana commented on Tokyo"}] = feed(ana)
      assert %Event{status: "sent"} = repo.get!(Event, event.id)
      assert Chime.counts("user:1") == %{unseen: 1, unread: 1}

      # Its time again does nothing.
      run_scheduled(minutes(62))
      assert [_] = feed(ana)
    end

    test "its job notifies", %{repo: repo} do
      ana = person!(1)
      {:ok, event} = comment!(ana, at: minutes(5))
      assert :ok = Chime.Worker.perform(%Oban.Job{args: %{"job" => "notify", "id" => event.id}})
      assert [_] = feed(ana)
      _ = repo
    end

    test "the guard decides when it is scheduled" do
      ana = person!(1)
      rui = person!(2)

      {:ok, event} =
        Chime.notify(
          ChimeTest.ChannelMessage,
          %{to: [ana, rui], text: "Hi", author: "x", blocked: ["user:2"]},
          at: minutes(5)
        )

      assert event.audience == ["user:1"]
      run_scheduled(minutes(6))
      assert [_] = feed(ana)
      assert feed(rui) == []
    end

    test "a scheduled notification cancelled is not sent" do
      ana = person!(1)
      {:ok, _} = comment!(ana, at: minutes(5), key: "c:1")
      assert {:ok, %{deliveries: 0}} = Chime.cancel("c:1")
      run_scheduled(minutes(6))
      assert feed(ana) == []
      assert [%Event{status: "cancelled"}] = events(ChimeTest.NewComment)
    end

    test "a sent notification cancelled: its waiting email is skipped, and the feed keeps it" do
      ana = person!(1)
      {:ok, _} = comment!(ana, key: "c:1")
      assert {:ok, %{deliveries: 2, removed: 0}} = Chime.cancel("c:1")

      assert [%Delivery{status: "skipped", reason: "the notification was cancelled"}] =
               deliveries(ana, channel: :email)

      assert [_] = feed(ana)
      assert deliver(at: minutes(11), channel: :email) == []
    end

    test "cancelled with feed: :remove, out of the feed, but a group with other events" do
      ana = person!(1)
      rui = person!(2)
      {:ok, _} = comment!(ana, key: "c:1", story: "A")
      {:ok, _} = comment!(rui, key: "c:2", story: "B", author: "Kenji")
      {:ok, _} = comment!(rui, key: "c:3", story: "B", author: "Mei")
      Chime.subscribe("user:1")

      assert {:ok, %{removed: 1}} = Chime.cancel("c:1", feed: :remove)
      assert feed(ana) == []
      assert Chime.counts("user:1") == %{unseen: 0, unread: 0}
      assert_receive {Chime, :updated, %{unread: 0}}

      assert {:ok, %{removed: 0}} = Chime.cancel("c:3", feed: :remove)
      assert [%{count: 2}] = feed(rui)
    end

    test "an unknown key" do
      assert {:error, :not_found} = Chime.cancel("nope")
    end
  end
end
