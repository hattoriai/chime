defmodule Chime.Migrations do
  @moduledoc """
  The tables of Chime, in a migration of the app.

      $ mix chime.gen.migration

  writes a migration that pins the latest version:

      defmodule MyApp.Repo.Migrations.AddChime do
        use Ecto.Migration

        def up, do: Chime.Migrations.up(version: 1)
        def down, do: Chime.Migrations.down(to: 0)
      end

  The versions are `PhoenixMountable.Migrations`: tracked in the app's
  database (per prefix), and run on PostgreSQL and on SQLite. A later
  version of Chime that changes the tables has a new version;
  `mix chime.gen.migration` then writes the migration that upgrades.

  The tables (version 1):

    * `chime_events` - each call of `Chime.notify/3`, once, with its data;
    * `chime_notifications` - each person's notifications: the feed, and
      what the deliveries hang from;
    * `chime_deliveries` - each notification by each channel but the
      feed, and what became of it;
    * `chime_preferences` - the settings people changed;
    * `chime_counts` - each person's counts of unseen and unread.

  `up/1` takes `:version` and `:prefix` (the schema of the tables, in
  PostgreSQL); `down/1` takes `:to` and `:prefix`.
  """

  use PhoenixMountable.Migrations,
    otp_app: :chime,
    versions: [Chime.Migrations.V1],
    gen_task: "chime.gen.migration"
end
