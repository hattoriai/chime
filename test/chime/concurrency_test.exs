defmodule Chime.ConcurrencyTest do
  use ExUnit.Case
  # Writers in parallel, outside the sandbox, on PostgreSQL in a schema of
  # its own: the counts and the groups stay whole.
  @moduletag :postgres

  import Ecto.Query

  test "parallel notifications and reads keep the counts whole, and groups whole" do
    repo = ChimeTest.PostgresMigrationsRepo
    repo.query!(~s(DROP SCHEMA IF EXISTS "conc" CASCADE))
    repo.query!(~s(CREATE SCHEMA "conc"))
    repo.query!("DELETE FROM schema_migrations WHERE version = 20261025")
    Ecto.Migrator.run(repo, [{20_261_025, ChimeTest.ConcMigration}], :up, all: true, log: false)

    {:ok, _} = Oban.start_link(name: ConcOban, repo: repo, prefix: "conc", testing: :manual)

    config =
      Chime.Config.new(ChimeTest.DataCase.config_opts(repo, ConcOban) ++ [prefix: "conc"])

    Chime.Config.put(config)
    ChimeTest.People.reset()

    ids = for n <- 1..5, do: "user:#{n}"

    1..40
    |> Task.async_stream(
      fn i ->
        if rem(i, 5) == 0 do
          Chime.mark_read(Enum.random(ids), :all)
        else
          {:ok, _} =
            Chime.notify(ChimeTest.NewComment, %{
              to: ids,
              story: "S#{rem(i, 3)}",
              text: "x",
              author: "A#{i}"
            })
        end
      end,
      max_concurrency: 10,
      timeout: 60_000
    )
    |> Stream.run()

    for id <- ids do
      ns =
        repo.all(from(n in Chime.Notification, where: n.recipient == ^id and n.in_feed),
          prefix: "conc"
        )

      unread = Enum.count(ns, &is_nil(&1.read_at))
      unseen = Enum.count(ns, &is_nil(&1.seen_at))
      assert Chime.counts(id) == %{unseen: unseen, unread: unread}, "#{id}"
      events = Enum.sum(Enum.map(ns, & &1.count))
      assert events == 32, "#{id}: #{events} events of 32"
    end
  after
    ChimeTest.PostgresMigrationsRepo.query!(~s(DROP SCHEMA IF EXISTS "conc" CASCADE))
  end
end

defmodule ChimeTest.ConcMigration do
  use Ecto.Migration

  def up do
    Oban.Migration.up(prefix: "conc")
    Chime.Migrations.up(version: 1, prefix: "conc")
  end
end
