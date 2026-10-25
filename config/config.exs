import Config

# Swoosh is optional, for the :email channel: the app gives its own
# mailer, and Chime needs no HTTP client of Swoosh's.
config :swoosh, :api_client, false

if config_env() == :test do
  config :logger, level: :warning
  config :phoenix, :json_library, JSON

  # The notifications, tested with both adapters. The PostgreSQL tests
  # are tagged :postgres, and run when the database is reachable (see
  # test/test_helper.exs).
  config :chime, ChimeTest.SQLiteRepo,
    database: Path.expand("../tmp/chime_test.sqlite3", __DIR__),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5

  config :chime, ChimeTest.PostgresRepo,
    url:
      System.get_env(
        "CHIME_TEST_DATABASE_URL",
        "ecto://postgres:postgres@localhost/chime_test"
      ),
    pool: Ecto.Adapters.SQL.Sandbox,
    pool_size: 5

  # A database of its own for the checks of Chime's migrations, which
  # empty it (test/chime/migrations_test.exs), and on PostgreSQL a schema
  # of its own (a prefix).
  config :chime, ChimeTest.MigrationsRepo,
    database: Path.expand("../tmp/chime_migrations_test.sqlite3", __DIR__),
    pool_size: 1

  config :chime, ChimeTest.PostgresMigrationsRepo,
    url:
      System.get_env(
        "CHIME_TEST_DATABASE_URL",
        "ecto://postgres:postgres@localhost/chime_test"
      ),
    pool_size: 2

  config :chime, ecto_repos: [ChimeTest.SQLiteRepo, ChimeTest.PostgresRepo]

  config :chime, ChimeTest.Mailer, adapter: Swoosh.Adapters.Test

  # A forgotten version of Chime.Migrations fails the tests.
  config :phoenix_mountable, pending_migrations: :raise
end
