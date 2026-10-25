defmodule Chime.CleanupTest do
  use ChimeTest.DataCase

  for_each_repo do
    test "the notifications past :keep_days go, with their deliveries and events; the counts follow",
         %{repo: repo} do
      ana = person!(1)
      old = DateTime.add(DateTime.utc_now(), -200, :day)
      {:ok, _} = comment!(ana, story: "Old", now: old)
      {:ok, _} = comment!(ana, story: "New")
      assert Chime.counts("user:1") == %{unseen: 2, unread: 2}

      Chime.Cleanup.run(Chime.Config.get(), DateTime.utc_now())

      assert [%{title: "Ana commented on New"}] = Chime.Test.feed(ana)
      assert Chime.counts("user:1") == %{unseen: 1, unread: 1}
      assert repo.aggregate(Event, :count) == 1
      assert repo.aggregate(Delivery, :count) == 2
    end

    test "with :keep_days nil, nothing goes", ctx do
      config = reconfigure(ctx, keep_days: nil)
      {:ok, _} = comment!(person!(1), now: DateTime.add(DateTime.utc_now(), -900, :day))
      Chime.Cleanup.run(config, DateTime.utc_now())
      assert [_] = Chime.feed("user:1")
    end
  end
end
