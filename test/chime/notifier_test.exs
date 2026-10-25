defmodule Chime.NotifierTest do
  use ExUnit.Case, async: true

  test "a notifier's declarations" do
    assert [
             %{channel: "feed", wait: 0, if: [], unless: []},
             %{channel: "email", wait: 600, unless: [:read]},
             %{channel: "telegram", if: [:telegram?]}
           ] = ChimeTest.NewComment.__chime__(:deliveries)

    assert ChimeTest.NewComment.__chime__(:kind) == "new_comment"
    assert ChimeTest.NewComment.__chime__(:category) == "comments"
    assert ChimeTest.NewComment.__chime__(:group_window) == 600
    assert ChimeTest.Followed.__chime__(:kind) == "followed"
  end

  test "the default data is the params as JSON" do
    assert ChimeTest.PaymentFailed.data(%{amount: "€9", at: ~D[2026-10-25]}) == %{
             "amount" => "€9",
             "at" => "2026-10-25"
           }

    assert_raise ArgumentError, ~r/write data\/1/, fn ->
      ChimeTest.PaymentFailed.data(%{pid: self()})
    end
  end

  test "what does not compile" do
    for {code, message} <- [
          {"use Chime.Notifier", ~r/needs a :category/},
          {"use Chime.Notifier, category: :c\ndeliver :feed\ndeliver :feed", ~r/twice/},
          {"use Chime.Notifier, category: :c\ndeliver :feed, wait: 5", ~r/the feed goes at once/},
          {"use Chime.Notifier, category: :c\ndeliver :email, wait: {1, :year}",
           ~r/:wait must be/},
          {"use Chime.Notifier, category: :c\ndeliver :email, if: :read",
           ~r/a condition of :unless/},
          {"use Chime.Notifier, category: :c\ndeliver :email, unless: :nope",
           ~r/defines no nope\/2/},
          {"use Chime.Notifier, category: :c\ndeliver :email, sooner: true",
           ~r/takes :wait, :if and :unless/}
        ] do
      name = "Chime.NotifierTest.N#{System.unique_integer([:positive])}"

      assert_raise ArgumentError, message, fn ->
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          Code.compile_string("defmodule #{name} do\n#{code}\nend")
        end)
      end
    end
  end

  test "a missing feed/2 or email/3 warns" do
    warning =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        Code.compile_string("""
        defmodule Chime.NotifierTest.Warns do
          use Chime.Notifier, category: :c
          deliver :feed
          deliver :email
        end
        """)
      end)

    assert warning =~ "defines no feed/2"
    assert warning =~ "defines no email/3"
  end
end
