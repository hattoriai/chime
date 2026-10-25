defmodule Chime.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/hattoriai/chime"

  # CHIME_OLDEST=1 resolves the oldest Phoenix and LiveView that Chime
  # supports, for the CI job that tests them.
  @oldest System.get_env("CHIME_OLDEST") in ["1", "true"]

  def project do
    [
      app: :chime,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit],
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"}
      ],
      package: package(),
      docs: docs(),
      description: description(),
      name: "Chime",
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # The notifications live in the app's database, on PostgreSQL or
      # SQLite.
      {:ecto, "~> 3.13"},
      {:ecto_sql, "~> 3.13"},
      {:ecto_sqlite3, "~> 0.22", only: [:dev, :test]},
      # Chime's words in the app's languages, by the app's own backend.
      {:gettext, "~> 0.26 or ~> 1.0", optional: true},
      {:postgrex, "~> 0.19", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:lazy_html, "~> 0.1", only: :test},
      # Every delivery but the feed is a job: retried through deploys and
      # crashes, delayed, and in the write's transaction.
      {:oban, "~> 2.19"},
      # The JSON API, the page to unsubscribe and the migrations.
      {:phoenix_mountable, "~> 0.2.4"},
      {:phoenix, if(@oldest, do: "~> 1.7.14", else: "~> 1.7.14 or ~> 1.8")},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, if(@oldest, do: "~> 1.1.0", else: "~> 1.1")},
      # The :email channel, with the app's own mailer.
      {:swoosh, "~> 1.17", optional: true},
      {:telemetry, "~> 1.0"}
    ]
  end

  defp description do
    "Notifications for Phoenix: one event to an in-app feed, email and channels of your own, with read and unread, grouping, digests, preferences, a log of every decision, a JSON API for any frontend and a LiveView bell."
  end

  defp package do
    [
      name: "chime",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(
        lib
        priv/static/chime.css
        priv/gettext/chime.pot
        mix.exs
        .formatter.exs
        guides
        README.md
        CHANGELOG.md
        LICENSE
        NOTICE
      )
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      assets: %{"media" => "media"},
      extras: [
        "README.md",
        "guides/quickstart.md",
        "guides/notifiers.md",
        "guides/channels.md",
        "guides/preferences.md",
        "guides/workspaces.md",
        "guides/explain.md",
        "guides/live_view.md",
        "guides/any_frontend.md",
        "guides/languages.md",
        "guides/testing.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "SECURITY.md"
      ],
      groups_for_extras: [
        Guides: [
          "guides/quickstart.md",
          "guides/notifiers.md",
          "guides/channels.md",
          "guides/preferences.md",
          "guides/workspaces.md",
          "guides/explain.md",
          "guides/live_view.md",
          "guides/any_frontend.md",
          "guides/languages.md",
          "guides/testing.md"
        ]
      ],
      groups_for_modules: [
        Notifications: [
          Chime,
          Chime.Config,
          Chime.Notifier,
          Chime.Recipient,
          Chime.Resolver,
          Chime.Event,
          Chime.Notification,
          Chime.Feed,
          Chime.Preferences,
          Chime.Explain,
          Chime.Messages
        ],
        Channels: [
          Chime.Channel,
          Chime.Message,
          Chime.Channels.Email,
          Chime.Delivery,
          Chime.Digest
        ],
        "In the app": [Chime.Live, Chime.Live.State, Chime.Components],
        Mounting: [Chime.Router, Chime.API, Chime.Token, Chime.Unsubscribe],
        Database: [Chime.Migrations],
        Testing: [Chime.Test]
      ]
    ]
  end

  defp aliases do
    [
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "test"
      ]
    ]
  end
end
