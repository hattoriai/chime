defmodule Chime.PreferencesTest do
  use ChimeTest.DataCase

  import Chime.Test

  for_each_repo do
    test "each category's settings by channel, its defaults and the person's own" do
      person!(1)
      assert :ok = Chime.put_preference("user:1", :comments, :email, :daily)

      assert [
               %{category: %{key: "comments", label: "Comments"}, settings: comments},
               %{category: %{key: "followers"}, settings: followers},
               %{category: %{key: "billing", required: true}, settings: billing}
             ] = Chime.preferences("user:1")

      assert comments == %{"feed" => "on", "email" => "daily", "telegram" => "on"}
      assert followers == %{"feed" => "on", "email" => "weekly", "telegram" => "on"}
      assert billing == %{"feed" => "on", "email" => "on", "telegram" => "on"}
    end

    test "what cannot be changed" do
      assert {:error, :required} = Chime.put_preference("user:1", :billing, :email, :off)
      assert {:error, :unknown_category} = Chime.put_preference("user:1", :nope, :email, :off)
      assert {:error, :unknown_channel} = Chime.put_preference("user:1", :comments, :sms, :off)

      assert {:error, :invalid_setting} =
               Chime.put_preference("user:1", :comments, :telegram, :daily)

      assert {:error, :invalid_setting} =
               Chime.put_preference("user:1", :comments, :email, :hourly)
    end

    test "a channel turned off is skipped at once, and the log says when" do
      ana = person!(1, telegram: "chat")
      :ok = Chime.put_preference("user:1", :comments, :email, :off)
      {:ok, _} = comment!(ana)

      assert [
               %Delivery{
                 status: "skipped",
                 reason: "the person turned off email for comments on " <> _
               }
             ] =
               deliveries(ana, channel: :email)
    end

    test "a channel turned off after the notification is skipped at its time" do
      ana = person!(1)
      {:ok, _} = comment!(ana)
      :ok = Chime.put_preference("user:1", :comments, :email, :off)

      assert [
               %Delivery{
                 status: "skipped",
                 reason: "the person turned off email for comments" <> _
               }
             ] =
               deliver(at: minutes(11), channel: :email)
    end

    test "the feed turned off: not in it, not counted, and the email still goes" do
      ana = person!(1)
      :ok = Chime.put_preference("user:1", :comments, :feed, :off)
      {:ok, _} = comment!(ana)

      assert feed(ana) == []
      assert Chime.counts("user:1") == %{unseen: 0, unread: 0}
      assert [%Delivery{status: "sent"}] = deliver(at: minutes(11), channel: :email)
    end

    test "a required notification goes whatever the person turned off, with no link to unsubscribe" do
      ana = person!(1)
      :ok = Chime.put_preference("user:1", :comments, :email, :off)
      {:ok, _} = Chime.notify(ChimeTest.PaymentFailed, %{amount: "€9"}, to: ana)

      assert [%{title: "Your payment of €9 failed"}] = feed(ana)
      assert [%Delivery{status: "sent"}] = deliver(channel: :email)

      assert_email_sent(fn email ->
        assert email.subject == "Your payment failed"
        refute email.headers["List-Unsubscribe"]
        true
      end)
    end

    test "a link to unsubscribe turns off its category's email" do
      ana = person!(1)
      url = Chime.unsubscribe_url(ana |> ChimeTest.Resolver.recipient(), "comments")
      "https://app.test/notifications/unsubscribe/" <> token = url

      assert {:ok, "user:1", "comments"} =
               Chime.Token.verify_unsubscribe(Chime.Config.get(), token)

      :ok = Chime.Preferences.unsubscribe(Chime.Config.get(), "user:1", "comments")
      assert %{"email" => "off"} = hd(Chime.preferences("user:1")).settings
    end

    test "a digest's link turns off every email but the required" do
      person!(1)
      :ok = Chime.put_preference("user:1", :comments, :email, :daily)
      :ok = Chime.Preferences.unsubscribe(Chime.Config.get(), "user:1", "*")

      assert [comments, followers, billing] = Chime.preferences("user:1")
      assert comments.settings["email"] == "off"
      assert followers.settings["email"] == "off"
      assert billing.settings["email"] == "on"
      assert comments.settings["feed"] == "on"
    end
  end
end
