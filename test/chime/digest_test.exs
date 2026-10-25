defmodule Chime.DigestTest do
  use ChimeTest.DataCase

  import Chime.Test

  alias Chime.Digest

  @digest %{at: 9, weekly_on: :monday}

  test "the last digest times, daily and weekly" do
    # Sunday 2026-10-25.
    assert {~U[2026-10-25 09:00:00Z], ~U[2026-10-19 09:00:00Z]} =
             Digest.boundaries(@digest, nil, ~U[2026-10-25 10:00:00Z])

    assert {~U[2026-10-24 09:00:00Z], ~U[2026-10-19 09:00:00Z]} =
             Digest.boundaries(@digest, nil, ~U[2026-10-25 08:59:00Z])

    # Monday 2026-10-26, after nine.
    assert {~U[2026-10-26 09:00:00Z], ~U[2026-10-26 09:00:00Z]} =
             Digest.boundaries(@digest, nil, ~U[2026-10-26 09:00:05Z])

    # A time zone the database does not know is UTC.
    assert {~U[2026-10-25 09:00:00Z], _} =
             Digest.boundaries(@digest, "Mars/Olympus", ~U[2026-10-25 10:00:00Z])
  end

  for_each_repo do
    test "the weekly digest of a category's emails, on its day" do
      ana = person!(1, name: "Ana", email: "ana@app.test")
      # Followers are weekly by default; Sunday the 25th.
      now = ~U[2026-10-25 12:00:00Z]
      {:ok, _} = Chime.notify(ChimeTest.Followed, %{"name" => "Rui"}, to: ana, now: now)
      {:ok, _} = Chime.notify(ChimeTest.Followed, %{"name" => "Kenji"}, to: ana, now: now)

      assert [%Delivery{status: "digest", reason: "weekly"}, %Delivery{status: "digest"}] =
               deliver(at: now)

      refute_email_sent()

      run_digests(~U[2026-10-26 08:00:00Z])
      refute_email_sent()

      run_digests(~U[2026-10-26 09:00:05Z])

      assert_email_sent(fn email ->
        assert email.subject == "Your notifications of the week"
        assert email.to == [{"Ana", "ana@app.test"}]
        assert email.text_body =~ "followed"
        assert email.headers["List-Unsubscribe"]
      end)

      assert [%Delivery{status: "digested", reason: "weekly"}, %Delivery{status: "digested"}] =
               deliveries(ana)

      run_digests(~U[2026-10-27 09:00:05Z])
      refute_email_sent()
    end

    test "a daily digest of the feed's words, with whole links" do
      ana = person!(1)
      :ok = Chime.put_preference("user:1", :comments, :email, :daily)
      now = ~U[2026-10-25 12:00:00Z]
      {:ok, _} = comment!(ana, now: now)

      [%Delivery{status: "digest"}] = deliver(at: minutes(11, now), channel: :email)
      run_digests(~U[2026-10-26 09:30:00Z])

      assert_email_sent(fn email ->
        assert email.subject == "Your notifications of the day"
        assert email.text_body =~ "Ana commented on Tokyo"
        assert email.html_body =~ ~s(<a href="https://app.test/stories/Tokyo">)
      end)
    end

    test "the app's own digest email", ctx do
      reconfigure(ctx, digest: [email: ChimeTest.DigestEmail])
      ana = person!(1)
      now = ~U[2026-10-25 12:00:00Z]
      {:ok, _} = Chime.notify(ChimeTest.Followed, %{"name" => "Rui"}, to: ana, now: now)
      deliver(at: now)
      run_digests(~U[2026-10-26 10:00:00Z])

      assert_email_sent(subject: "1 weekly")
    end
  end
end
