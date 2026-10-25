defmodule Chime.NotifyTest do
  use ChimeTest.DataCase

  import Chime.Test

  @moduletag :capture_log

  for_each_repo do
    test "a notification for each person, in their feed, with their counts" do
      ana = person!(1)
      rui = person!(2)

      assert {:ok, %Event{recipients: 2, kind: "new_comment", category: "comments"}} =
               comment!([ana, rui], author: "Kenji")

      assert [
               %{
                 title: "Kenji commented on Tokyo",
                 body: "Lovely.",
                 url: "/stories/Tokyo",
                 count: 1
               }
             ] =
               feed(ana)

      assert Chime.counts("user:1") == %{unseen: 1, unread: 1}
      assert Chime.counts("user:2") == %{unseen: 1, unread: 1}
      assert Chime.counts("user:3") == %{unseen: 0, unread: 0}

      assert %Notification{count: 1} =
               assert_notified(ChimeTest.NewComment, to: ana, data: %{story: "Tokyo"})

      refute_notified(ChimeTest.NewComment, to: person!(3))
    end

    test "the people of the notifier, its own or as ids and recipients, each once" do
      person!(1)
      person!(2)

      {:ok, event} =
        Chime.notify(ChimeTest.NewComment, %{
          to: ["user:1", %Recipient{id: "user:1"}, %ChimeTest.User{id: 2}],
          story: "A",
          text: "x",
          author: "Ana"
        })

      assert event.recipients == 2
    end

    test "an idempotency key makes one event of two calls" do
      ana = person!(1)
      assert {:ok, event} = comment!(ana, key: "comment:1")
      assert {:error, :duplicate, ^event} = comment!(ana, key: "comment:1", text: "Again")
      assert [%{count: 1, body: "Lovely."}] = feed(ana)
    end

    test "the events of a group join the person's open notification" do
      ana = person!(1)
      {:ok, _} = comment!(ana, author: "Rui")
      Chime.mark_seen("user:1")
      {:ok, _} = comment!(ana, author: "Kenji", text: "Wow.")
      {:ok, _} = comment!(ana, author: "Rui", text: "Again.")

      assert [%{title: "Rui and Kenji commented on Tokyo", count: 3, body: "Again.", seen: false}] =
               feed(ana)

      assert [%{"name" => "Rui"}, %{"name" => "Kenji"}] = hd(feed(ana)).actors
      assert Chime.counts("user:1") == %{unseen: 1, unread: 1}

      # Another story is another group.
      {:ok, _} = comment!(ana, story: "Kyoto")
      assert [%{title: "Ana commented on Kyoto"}, %{count: 3}] = feed(ana)
    end

    test "a read group, or one past its window, takes no more events" do
      ana = person!(1)
      now = DateTime.utc_now()
      {:ok, _} = comment!(ana, now: now)
      Chime.mark_read("user:1", :all)
      {:ok, _} = comment!(ana, now: minutes(1, now))
      assert [%{count: 1, read: false}, %{count: 1, read: true}] = feed(ana)

      {:ok, _} = comment!(ana, now: minutes(11, now))
      assert [%{count: 1}, %{count: 1}, %{count: 1}] = feed(ana)
    end

    test "the email waits, and goes with the person's address and a link to unsubscribe" do
      ana = person!(1, name: "Ana", email: "ana@app.test")
      {:ok, _} = comment!(ana)

      assert [] = deliver(channel: :email)

      assert [%Delivery{status: "sent", channel: "email", attempts: 1}] =
               deliver(at: minutes(11), channel: :email)

      assert_email_sent(fn email ->
        assert email.subject == "Ana commented on Tokyo"
        assert email.to == [{"Ana", "ana@app.test"}]
        assert email.from == {"The app", "hello@app.test"}

        assert ["<https://app.test/notifications/mail/unsubscribe/" <> _] = [
                 email.headers["List-Unsubscribe"]
               ]

        assert email.headers["List-Unsubscribe-Post"] == "List-Unsubscribe=One-Click"
      end)
    end

    test "an email unless read is skipped when the person read it, and the log says when" do
      ana = person!(1)
      {:ok, _} = comment!(ana)
      [%{id: id}] = feed(ana)
      Chime.mark_read("user:1", [id])

      assert [%Delivery{status: "skipped", reason: "read in the feed at " <> _}] =
               deliver(at: minutes(11), channel: :email)

      refute_email_sent()
      assert explain(id) =~ ~r/email\s+skipped\s+read in the feed at/
    end

    test "the events of a group that come while its email waits go in that one email" do
      ana = person!(1)
      {:ok, _} = comment!(ana, author: "Rui")
      {:ok, _} = comment!(ana, author: "Kenji")

      assert [%Delivery{status: "sent"}] = deliver(at: minutes(11), channel: :email)
      assert_email_sent(subject: "Kenji and Rui commented on Tokyo")
    end

    test "a channel's condition, and the app's own channel" do
      ana = person!(1, telegram: "chat-1")
      rui = person!(2)
      {:ok, _} = comment!([ana, rui])

      deliveries = deliver(channel: :telegram)
      assert_received {:telegram, "chat-1", "New comment on Tokyo"}

      assert %{
               "user:1" => %{status: "sent", ref: "tg-chat-1"},
               "user:2" => %{status: "skipped", reason: "if telegram? was false"}
             } =
               Map.new(deliveries, &{&1.recipient, &1})
    end

    test "a channel's error waits for another attempt, and fails on the last" do
      ana = person!(1, telegram: "fails")
      {:ok, _} = comment!(ana)

      assert [%Delivery{status: "scheduled", attempts: 1, reason: "attempt 1: :timeout"}] =
               deliver(channel: :telegram, last_attempt: false)

      assert [%Delivery{status: "failed", attempts: 2, reason: ":timeout"}] =
               deliver(channel: :telegram)
    end

    test "a person the resolver no longer gives is skipped" do
      ana = person!(1)
      {:ok, _} = comment!(ana)
      ChimeTest.People.delete("user:1")

      assert [%Delivery{status: "skipped", reason: "the resolver no longer gives the person"}] =
               deliver(at: minutes(11), channel: :email)
    end

    test "a person with no address is skipped" do
      ana = person!(1, email: nil)
      {:ok, _} = comment!(ana)

      assert [%Delivery{status: "skipped", reason: "the person has no email address"}] =
               deliver(at: minutes(11), channel: :email)
    end

    test "the deliveries are Oban jobs at their time", %{repo: repo} do
      ana = person!(1)
      {:ok, _} = comment!(ana)

      # The email in ten minutes, the telegram now.
      assert [now, later] = repo.all(Oban.Job) |> Enum.sort_by(& &1.scheduled_at, DateTime)
      assert %Oban.Job{worker: "Chime.Worker", args: %{"job" => "deliver"}} = later
      assert DateTime.diff(later.scheduled_at, DateTime.utc_now()) in 590..600
      assert DateTime.diff(now.scheduled_at, DateTime.utc_now()) in -5..0
    end

    test "a notification without a feed is not in it, and its email goes" do
      ana = person!(1)
      {:ok, _} = Chime.notify(ChimeTest.Followed, %{"name" => "Rui"}, to: ana)
      assert feed(ana) == []
      assert Chime.counts("user:1") == %{unseen: 0, unread: 0}
    end

    test "a notifier must be one, with a category of the config and channels it has", ctx do
      assert_raise ArgumentError, ~r/is not a Chime.Notifier/, fn -> Chime.notify(String, %{}) end

      reconfigure(ctx, mailer: nil, email_from: nil)

      assert_raise ArgumentError, ~r/no :mailer/, fn -> comment!(person!(1)) end
    end

    test "the people's pages hear of it" do
      ana = person!(1)
      Chime.subscribe("user:1")
      {:ok, _} = comment!(ana)
      assert_receive {Chime, :notified, %{unseen: 1, unread: 1}}

      Chime.mark_seen("user:1")
      assert_receive {Chime, :updated, %{unseen: 0, unread: 1}}
    end
  end
end
