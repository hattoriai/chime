defmodule Chime.GuardsTest do
  use ChimeTest.DataCase

  import Chime.Test

  for_each_repo do
    test "the person who did it is not told of it" do
      ana = person!(1)
      rui = person!(2)

      {:ok, event} =
        Chime.notify(ChimeTest.ChannelMessage, %{to: [ana, rui], text: "Hi", author: "user:1"})

      assert event.recipients == 1
      refute_notified(ChimeTest.ChannelMessage, to: ana)
      assert_notified(ChimeTest.ChannelMessage, to: rui)
    end

    test "unless the notifier tells them too" do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.SelfToo, %{author: "user:1"}, to: ana)
      assert_notified(ChimeTest.SelfToo, to: ana)
    end

    test "notify?/2: a person the guard says no to gets nothing, by any channel" do
      ana = person!(1)
      rui = person!(2)

      {:ok, event} =
        Chime.notify(ChimeTest.ChannelMessage, %{
          to: [ana, rui],
          text: "Hi",
          author: "user:9",
          blocked: ["user:2"]
        })

      assert event.recipients == 1
      refute_notified(ChimeTest.ChannelMessage, to: rui)
      assert deliveries(rui) == []
      assert [%Delivery{channel: "email"}] = deliveries(ana)
    end

    test "the guard gets the people as the resolver gives them, for ids" do
      person!(1)

      {:ok, event} =
        Chime.notify(ChimeTest.ChannelMessage, %{
          to: ["user:1", "user:404"],
          text: "Hi",
          author: "x"
        })

      # user:404 is not one of the app's people: not notified.
      assert event.recipients == 1
    end

    test "the feed's condition keeps it out of the feed, the email still goes, and the log says why" do
      ana = person!(1)
      rui = person!(2)

      {:ok, _} =
        Chime.notify(ChimeTest.ChannelMessage, %{
          to: [ana, rui],
          text: "Hi",
          author: "x",
          members: ["user:2"]
        })

      assert feed(ana) == []
      assert [%{title: "Hi"}] = feed(rui)
      assert Chime.counts("user:1") == %{unseen: 0, unread: 0}

      [%Delivery{notification_id: id} = feed_delivery, %Delivery{channel: "email"}] =
        deliveries(ana) |> Enum.sort_by(&(&1.channel != "feed"))

      assert %Delivery{channel: "feed", status: "skipped", reason: "if can_read? was false"} =
               feed_delivery

      assert explain(id) =~ ~r/feed\s+skipped\s+if can_read\? was false/
      refute explain(id) =~ ~r/feed\s+shown/

      assert [%Delivery{status: "sent"}] = deliver(at: minutes(2), channel: :email, to: ana)
    end

    test "the feed turned off by the person is in the log too" do
      ana = person!(1)
      :ok = Chime.put_preference("user:1", :comments, :feed, :off)
      {:ok, _} = comment!(ana)

      [
        %Delivery{
          channel: "feed",
          reason: "the person turned off feed for comments" <> _,
          notification_id: id
        }
        | _
      ] =
        deliveries(ana, channel: :feed)

      assert explain(id) =~ ~r/feed\s+skipped\s+the person turned off feed/
    end
  end

  test "a feed with :wait, or unless it is read, does not compile" do
    for {code, message} <- [
          {"deliver :feed, wait: 5", ~r/no :wait/},
          {"deliver :feed, unless: :read", ~r/before it can be read/}
        ] do
      assert_raise ArgumentError, message, fn ->
        Code.compile_string(
          "defmodule Chime.GuardsTest.N#{System.unique_integer([:positive])} do\nuse Chime.Notifier, category: :c\n#{code}\nend"
        )
      end
    end
  end
end
