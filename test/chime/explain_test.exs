defmodule Chime.ExplainTest do
  use ChimeTest.DataCase

  import Chime.Test

  for_each_repo do
    test "the log of a notification: each channel, what it decided and why" do
      ana = person!(1, telegram: "chat")
      now = ~U[2026-10-25 14:02:11.000000Z]
      {:ok, _} = comment!(ana, now: now)
      [n] = Chime.feed("user:1")

      deliver(at: now, channel: :telegram)
      Chime.mark_read("user:1", [n.id])
      deliver(at: minutes(11, now), channel: :email)

      text = explain(n)
      assert text =~ "2026-10-25 14:02:11Z  new_comment  to user:1  (comments)"
      assert text =~ ~r/14:02:11Z  feed\s+shown/
      assert text =~ ~r/telegram\s+sent\s+ref tg-chat/
      assert text =~ ~r/feed\s+seen/
      assert text =~ ~r/feed\s+read/
      assert text =~ ~r/email\s+skipped\s+read in the feed at/

      assert %{notification: %Notification{}, steps: steps} = Chime.explain(n.id)
      assert %{channel: "feed", status: "shown", reason: nil, at: now} in steps

      assert Chime.explain(Ecto.UUID.generate()) == nil
      assert Chime.Explain.format(nil) == "no such notification"
    end

    test "a waiting delivery, a group, and a digest in the log" do
      ana = person!(1)
      {:ok, _} = comment!(ana, author: "Rui")
      {:ok, _} = comment!(ana, author: "Kenji")
      [n] = Chime.feed("user:1")
      assert explain(n) =~ ~r/feed\s+grouped\s+2 events of story:Tokyo/
      assert explain(n) =~ ~r/email\s+scheduled\s+waits until/

      :ok = Chime.put_preference("user:1", :comments, :email, :weekly)
      deliver(at: minutes(11), channel: :email)
      assert explain(n) =~ ~r/email\s+digest\s+waits for the person's weekly digest/
    end
  end
end
