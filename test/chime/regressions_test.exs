defmodule Chime.RegressionsTest do
  use ChimeTest.DataCase

  import Chime.Test

  for_each_repo do
    test "two notifiers with the same group key keep their own notifications" do
      ana = person!(1)
      {:ok, _} = comment!(ana, author: "Rui")
      {:ok, _} = Chime.notify(ChimeTest.Liked, %{to: [ana], story: "Tokyo", author: "Kenji"})

      assert [
               %{title: "Kenji liked Tokyo", count: 1},
               %{title: "Rui commented on Tokyo", count: 1}
             ] =
               feed(ana)
    end

    test "a group joined after the person turned the feed off leaves the counts" do
      ana = person!(1)
      {:ok, _} = comment!(ana)
      :ok = Chime.put_preference("user:1", :comments, :feed, :off)
      {:ok, _} = comment!(ana, author: "Rui")

      assert feed(ana) == []
      assert Chime.counts("user:1") == %{unseen: 0, unread: 0}
    end

    test "the actors of a large group are counted beyond those kept" do
      ana = person!(1)
      for n <- 1..25, do: {:ok, _} = comment!(ana, author: "P#{n}")
      for n <- 24..25, do: {:ok, _} = comment!(ana, author: "P#{n}")

      assert [%{count: 27, title: "P25 and 24 others commented on Tokyo"}] = feed(ana)
    end

    test "a delivery that raises on its last attempt fails, and its group gets another" do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.Raises, %{}, to: ana)
      [%Delivery{id: id}] = deliveries(ana)

      assert_raise RuntimeError, "boom", fn ->
        Chime.Deliver.perform(Chime.Config.get(), id, true)
      end

      assert [%Delivery{status: "failed", reason: "boom", attempts: 1}] = deliveries(ana)

      {:ok, _} = Chime.notify(ChimeTest.Raises, %{}, to: ana)
      assert [%Delivery{status: "scheduled"}, %Delivery{status: "failed"}] = deliveries(ana)
    end

    test "the log of a notifier with no feed does not blame the person" do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.Followed, %{"name" => "Rui"}, to: ana)
      [%Delivery{notification_id: id}] = deliveries(ana)

      refute explain(id) =~ "turned off the feed"
      refute explain(id) =~ ~r/feed\s+skipped/
    end
  end
end
