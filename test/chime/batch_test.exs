defmodule Chime.BatchTest do
  use ChimeTest.DataCase

  for_each_repo do
    test "an event to more people than a batch, each once, with their counts and jobs", %{
      repo: repo
    } do
      ids = for n <- 1..2_100, do: "user:#{n}"
      Chime.subscribe("user:2100")

      assert {:ok, %Event{recipients: 2_100}} =
               Chime.notify(ChimeTest.NewComment, %{
                 to: ids,
                 story: "Big",
                 text: "x",
                 author: "Ana"
               })

      assert repo.aggregate(Notification, :count) == 2_100
      assert repo.aggregate(Delivery, :count) == 2 * 2_100
      assert repo.aggregate(Oban.Job, :count) == 2 * 2_100
      assert Chime.counts("user:2100") == %{unseen: 1, unread: 1}
      assert_receive {Chime, :notified, %{unseen: 1}}

      # The second event joins every open group.
      {:ok, _} =
        Chime.notify(ChimeTest.NewComment, %{to: ids, story: "Big", text: "y", author: "Rui"})

      assert repo.aggregate(Notification, :count) == 2_100
      assert [%{count: 2}] = Chime.Test.feed("user:1500")
      # The deliveries that wait take the group: no more of them.
      assert repo.aggregate(Delivery, :count) == 2 * 2_100
    end
  end
end
