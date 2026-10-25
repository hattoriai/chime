defmodule Chime.RulesTest do
  use ChimeTest.DataCase

  import Chime.Test

  @t0 ~U[2026-10-25 12:00:00.000000Z]

  defp dm!(to, text, at, from \\ "user:9") do
    {:ok, _} = Chime.notify(ChimeTest.DirectMessage, %{text: text, from: from}, to: to, now: at)
  end

  defp seconds(n, from \\ @t0), do: DateTime.add(from, n)

  for_each_repo do
    test "debounce: quick messages go as one email, a minute after the last" do
      ana = person!(1)
      dm!(ana, "Hi", @t0)
      dm!(ana, "Are you there?", seconds(40))
      dm!(ana, "Hello?", seconds(80))

      assert [] = deliver(at: seconds(100), channel: :email)
      assert [%Delivery{status: "sent"}] = deliver(at: seconds(141), channel: :email)
      assert_email_sent(subject: "3 from user:9")
    end

    test "debounce has its most: max_wait from the first" do
      ana = person!(1)
      for n <- 0..9, do: dm!(ana, "m#{n}", seconds(n * 50))

      [%Delivery{scheduled_at: at}] = deliveries(ana, channel: :email)
      assert at == seconds(300)
    end

    test "throttle: the next email of the group waits 15 minutes after the last" do
      ana = person!(1)
      dm!(ana, "Hi", @t0)
      [%Delivery{status: "sent"}] = deliver(at: seconds(61), channel: :email)
      assert_email_sent()

      # The group is still open: a new email waits for its time, then for the throttle.
      dm!(ana, "Again", seconds(120))

      assert [%Delivery{status: "scheduled", reason: "throttled: one email in 15 min"} = held] =
               deliver(at: seconds(181), channel: :email)

      assert held.scheduled_at == seconds(61 + 900)
      refute_email_sent()
      assert [%Delivery{status: "sent"}] = deliver(at: seconds(61 + 900), channel: :email)
    end

    test "quiet hours: nothing but the feed, and what waits goes in the morning", ctx do
      reconfigure(ctx, quiet_hours: {22, 8})
      ana = person!(1, telegram: "chat")
      night = ~U[2026-10-25 23:30:00.000000Z]
      dm!(ana, "Late", night)

      assert [_] = feed(ana)

      assert [%Delivery{status: "scheduled", reason: "quiet hours until 08:00"} = held] =
               deliver(at: seconds(61, night), channel: :email)

      assert held.scheduled_at == ~U[2026-10-26 08:00:00.000000Z]

      # The telegram of the notifier goes in quiet hours (quiet: false).
      assert [%Delivery{status: "sent"}] = deliver(at: night, channel: :telegram)
    end

    test "a person's own quiet hours, and none" do
      ana = person!(1, quiet_hours: {1, 6})
      rui = person!(2, quiet_hours: false)
      at = ~U[2026-10-25 02:00:00.000000Z]
      Chime.notify(ChimeTest.DirectMessage, %{text: "x", from: "user:9"}, to: [ana, rui], now: at)

      held = deliver(at: seconds(61, at), channel: :email)

      assert %{"user:1" => "scheduled", "user:2" => "sent"} =
               Map.new(held, &{&1.recipient, &1.status})
    end

    test "the config's limit of a channel, by person", ctx do
      reconfigure(ctx, limits: [email: {2, :hour}])
      ana = person!(1)

      for {from, n} <- [{"a", 0}, {"b", 1}, {"c", 2}] do
        dm!(ana, "x", seconds(n * 60), from)
      end

      deliver(at: seconds(65), channel: :email)
      deliver(at: seconds(125), channel: :email)

      assert [%Delivery{status: "scheduled", reason: "the limit: 2 by email in 1 h"}] =
               deliver(at: seconds(185), channel: :email)
    end

    test "required notifications are not held", ctx do
      reconfigure(ctx, quiet_hours: {22, 8}, limits: [email: {1, :day}])
      ana = person!(1)
      night = ~U[2026-10-25 23:30:00.000000Z]
      {:ok, _} = Chime.notify(ChimeTest.PaymentFailed, %{amount: "€9"}, to: ana, now: night)
      {:ok, _} = Chime.notify(ChimeTest.PaymentFailed, %{amount: "€10"}, to: ana, now: night)
      assert [%{status: "sent"}, %{status: "sent"}] = deliver(at: night, channel: :email)
    end

    test "a held delivery's job waits for the new time", %{repo: repo} do
      ana = person!(1)
      dm!(ana, "Hi", @t0)
      dm!(ana, "Again", seconds(40))
      [%Delivery{id: id}] = deliveries(ana, channel: :email)
      repo.delete_all(Oban.Job)

      # The job of the first time runs early: it gives Oban one at the new time.
      assert :ok = Chime.Deliver.perform(Chime.Config.get(), id, false, seconds(61))
      assert [%Oban.Job{scheduled_at: at}] = repo.all(Oban.Job)
      assert at == seconds(100)
      assert [%Delivery{status: "scheduled"}] = deliveries(ana, channel: :email)
    end
  end

  test "the options, checked" do
    for {code, message} <- [
          {"deliver :feed, throttle: 5", ~r/no :throttle/},
          {"deliver :email, max_wait: 5", ~r/the limit of :debounce/}
        ] do
      assert_raise ArgumentError, message, fn ->
        Code.compile_string(
          "defmodule Chime.RulesTest.N#{System.unique_integer([:positive])} do\nuse Chime.Notifier, category: :c\n#{code}\nend"
        )
      end
    end

    assert_raise ArgumentError, ~r/:quiet_hours/, fn ->
      Chime.Config.new(repo: R, pubsub: P, resolver: ChimeTest.Resolver, quiet_hours: {8, 8})
    end

    assert_raise ArgumentError, ~r/:limits/, fn ->
      Chime.Config.new(repo: R, pubsub: P, resolver: ChimeTest.Resolver, limits: [email: 3])
    end
  end
end
