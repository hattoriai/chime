defmodule Chime.MigrationsTest do
  use ExUnit.Case

  alias PhoenixMountable.Migrations.Test, as: MigrationsTest

  # Every version up, down and up again, an upgrade from each, and the
  # columns a host adds kept: on a SQLite database of its own, and on
  # PostgreSQL in a schema of its own (the prefix).
  test "the migrations, on SQLite" do
    MigrationsTest.run_suite(ChimeTest.MigrationsRepo, Chime.Migrations)
  end

  @tag :postgres
  test "the migrations, on PostgreSQL, in a prefix" do
    repo = ChimeTest.PostgresMigrationsRepo
    MigrationsTest.run_suite(repo, Chime.Migrations, prefix: "chime_migrations_test")
    repo.query!(~s(DROP SCHEMA IF EXISTS "chime_migrations_test" CASCADE))
  end

  test "version 1 makes Chime's tables, and its down drops them" do
    repo = ChimeTest.MigrationsRepo
    MigrationsTest.reset!(repo)
    MigrationsTest.up(repo, Chime.Migrations, version: 1)

    assert tables(repo) ==
             ~w(chime_counts chime_deliveries chime_events chime_notifications chime_preferences)

    MigrationsTest.down(repo, Chime.Migrations, to: 0)
    assert tables(repo) == []
  end

  defp tables(repo) do
    %{rows: rows} =
      repo.query!(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name LIKE 'chime_%' ORDER BY name"
      )

    List.flatten(rows)
  end
end
