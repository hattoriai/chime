defmodule Chime.ConfigTest do
  use ExUnit.Case, async: true

  alias Chime.Config

  @base [repo: ChimeTest.SQLiteRepo, pubsub: ChimeTest.PubSub, resolver: ChimeTest.Resolver]

  test "the options, checked" do
    config =
      Config.new(
        @base ++
          [
            oban: [name: MyOban, queue: :notifications],
            categories: [comments: [defaults: [email: :daily]]],
            channels: [telegram: {ChimeTest.Telegram, pid: nil}],
            digest: [at: 7, weekly_on: :friday],
            url: "https://app.test/"
          ]
      )

    assert config.oban == %{name: MyOban, queue: :notifications}

    assert [
             %{
               key: "comments",
               label: "Comments",
               required: false,
               defaults: %{"email" => "daily"}
             }
           ] = config.categories

    assert config.channels == %{"telegram" => {ChimeTest.Telegram, [pid: nil]}}
    assert config.digest == %{at: 7, weekly_on: :friday, email: nil}
    assert config.url == "https://app.test"
    assert Config.channel_names(config) == ["feed", "telegram"]
  end

  test "what it refuses" do
    for {opts, message} <- [
          {[], ~r/:repo/},
          {[repo: R, pubsub: P], ~r/:resolver/},
          {@base ++ [mailer: M], ~r/:email_from/},
          {@base ++ [secret_key_base: "short"], ~r/32 bytes/},
          {@base ++ [categories: [comments: [defaults: [email: :hourly]]]], ~r/:defaults/},
          {@base ++ [categories: ["comments"]], ~r/each of :categories/},
          {@base ++ [channels: [email: ChimeTest.Telegram]], ~r/Chime's own channel/},
          {@base ++ [channels: [sms: String]], ~r/not a Chime.Channel/},
          {@base ++ [digest: [at: 24]], ~r/an hour/},
          {@base ++ [digest: [weekly_on: :someday]], ~r/a day/},
          {@base ++ [keep_days: 0], ~r/:keep_days/},
          {@base ++ [oban: "x"], ~r/:oban/},
          {@base ++ [categories: [comments: [channels: [:sms]]]],
           ~r/name "sms", which is not a channel/},
          {@base ++ [categories: [comments: [channels: ["feed"]]]], ~r/channel names \(atoms\)/},
          {@base ++ [categories: [comments: [channels: []]]], ~r/a list of channels/}
        ] do
      assert_raise ArgumentError, message, fn -> Config.new(opts) end
    end
  end

  test "a category's channels: those it names, in the config's order; else all" do
    config =
      Config.new(
        @base ++
          [
            categories: [likes: [channels: [:telegram, :feed]], comments: []],
            channels: [telegram: ChimeTest.Telegram]
          ]
      )

    assert Config.category_channels(config, Config.category(config, "likes")) == [
             "feed",
             "telegram"
           ]

    assert Config.category_channels(config, Config.category(config, "comments")) == [
             "feed",
             "telegram"
           ]

    assert Config.category(config, "comments").channels == nil
  end

  test "a category the config does not name" do
    config = Config.new(@base ++ [categories: [comments: []]])

    assert_raise ArgumentError, ~r/"nope" is not one of the :categories/, fn ->
      Config.category(config, "nope")
    end

    assert %{key: "anything"} = Config.category(Config.new(@base), "anything")
  end
end
