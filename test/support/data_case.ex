defmodule ChimeTest.DataCase do
  @moduledoc """
  Tests on the database, run once on SQLite and once on PostgreSQL (when
  it is reachable): `use ChimeTest.DataCase` and write the tests in
  `for_each_repo do ... end`.

  The config of Chime is one for the node, so these tests are not async.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL.Sandbox

  using do
    quote do
      import ChimeTest.DataCase
      import Swoosh.TestAssertions
      alias Chime.{Delivery, Event, Notification, Recipient}
    end
  end

  @doc """
  Defines the tests of the block once for each repo, in a describe of its
  own, tagged :postgres for PostgreSQL.
  """
  defmacro for_each_repo(do: block) do
    for {name, repo, oban, tags} <- [
          {"SQLite", ChimeTest.SQLiteRepo, ChimeTest.SQLiteOban, []},
          {"PostgreSQL", ChimeTest.PostgresRepo, ChimeTest.PostgresOban, [postgres: true]}
        ] do
      quote do
        describe unquote(name) do
          @describetag unquote(tags)
          setup do: ChimeTest.DataCase.checkout(unquote(repo), unquote(oban))
          unquote(block)
        end
      end
    end
  end

  @doc false
  def checkout(repo, oban, opts \\ []) do
    pid = Sandbox.start_owner!(repo, shared: true)
    ExUnit.Callbacks.on_exit(fn -> Sandbox.stop_owner(pid) end)
    ChimeTest.People.reset()
    Process.register(self(), :chime_test)

    config = Chime.Config.new(Keyword.merge(config_opts(repo, oban), opts))
    Chime.Config.put(config)
    {:ok, repo: repo, oban: oban, config: config}
  end

  @doc false
  def config_opts(repo, oban) do
    [
      repo: repo,
      pubsub: ChimeTest.PubSub,
      resolver: ChimeTest.Resolver,
      oban: oban,
      mailer: ChimeTest.Mailer,
      email_from: {"The app", "hello@app.test"},
      secret_key_base: String.duplicate("chime-test-secret-", 4),
      unsubscribe_url: "https://app.test/notifications/unsubscribe",
      url: "https://app.test",
      categories: [
        comments: [label: "Comments", description: "On your stories"],
        followers: [label: "Followers", defaults: [email: :weekly]],
        billing: [label: "Billing", required: true]
      ],
      channels: [telegram: ChimeTest.Telegram],
      scheduler: false
    ]
  end

  @doc "Changes the config of the test: the options over the tests' own."
  def reconfigure(%{repo: repo, oban: oban}, opts) do
    config = Chime.Config.new(Keyword.merge(config_opts(repo, oban), opts))
    Chime.Config.put(config)
    config
  end

  @doc "A person of the app, kept so that the resolver gives them."
  def person!(n, attrs \\ []) do
    user =
      struct!(
        ChimeTest.User,
        Keyword.merge([id: n, name: "Person #{n}", email: "person#{n}@app.test"], attrs)
      )

    ChimeTest.People.put(ChimeTest.Resolver.recipient(user))
    user
  end

  @doc "A comment notification on a story, by an author, to people."
  def comment!(to, opts \\ []) do
    params = %{
      to: List.wrap(to),
      story: Keyword.get(opts, :story, "Tokyo"),
      text: Keyword.get(opts, :text, "Lovely."),
      author: Keyword.get(opts, :author, "Ana")
    }

    Chime.notify(ChimeTest.NewComment, params, Keyword.take(opts, [:key, :now]))
  end

  @doc "Minutes from now, or from a time."
  def minutes(n, from \\ DateTime.utc_now()), do: DateTime.add(from, n * 60)
end
