{:ok, _pid} = Phoenix.PubSub.Supervisor.start_link(name: ChimeTest.PubSub)
{:ok, _pid} = ChimeTest.People.start_link()
{:ok, _pid} = ChimeTest.Host.start()

{:ok, _pid} =
  Chime.Fanout.start_link(
    Chime.Config.new(ChimeTest.DataCase.config_opts(ChimeTest.SQLiteRepo, ChimeTest.SQLiteOban))
  )

# The notifications in a database: SQLite always, PostgreSQL when it is
# reachable (CHIME_TEST_DATABASE_URL, or postgres:postgres@localhost).
File.mkdir_p!(Path.expand("../tmp", __DIR__))

migrations = [{0, ChimeTest.ObanMigration}, {1, ChimeTest.Migration}]
migrate = fn repo -> Ecto.Migrator.run(repo, migrations, :up, all: true, log: false) end

File.rm(Path.expand("../tmp/chime_test.sqlite3", __DIR__))
_ = Ecto.Adapters.SQLite3.storage_up(ChimeTest.SQLiteRepo.config())
{:ok, _pid} = ChimeTest.SQLiteRepo.start_link()
migrate.(ChimeTest.SQLiteRepo)
Ecto.Adapters.SQL.Sandbox.mode(ChimeTest.SQLiteRepo, :manual)
{:ok, _pid} = ChimeTest.MigrationsRepo.start_link()

# An Oban for each repo, which keeps its jobs for the tests to run.
{:ok, _pid} =
  Oban.start_link(
    name: ChimeTest.SQLiteOban,
    repo: ChimeTest.SQLiteRepo,
    engine: Oban.Engines.Lite,
    testing: :manual
  )

postgres? =
  case Ecto.Adapters.Postgres.storage_up(ChimeTest.PostgresRepo.config()) do
    result when result in [:ok, {:error, :already_up}] ->
      {:ok, _pid} = ChimeTest.PostgresRepo.start_link()
      migrate.(ChimeTest.PostgresRepo)
      Ecto.Adapters.SQL.Sandbox.mode(ChimeTest.PostgresRepo, :manual)
      {:ok, _pid} = ChimeTest.PostgresMigrationsRepo.start_link()

      {:ok, _pid} =
        Oban.start_link(
          name: ChimeTest.PostgresOban,
          repo: ChimeTest.PostgresRepo,
          testing: :manual
        )

      true

    {:error, reason} ->
      IO.puts(
        "PostgreSQL is not reachable (#{inspect(reason)}): the :postgres tests are excluded"
      )

      false
  end

ExUnit.start(exclude: if(postgres?, do: [], else: [:postgres]))
