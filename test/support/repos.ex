defmodule ChimeTest.SQLiteRepo do
  @moduledoc "A repo on SQLite."
  use Ecto.Repo, otp_app: :chime, adapter: Ecto.Adapters.SQLite3
end

defmodule ChimeTest.PostgresRepo do
  @moduledoc "A repo on PostgreSQL."
  use Ecto.Repo, otp_app: :chime, adapter: Ecto.Adapters.Postgres
end

defmodule ChimeTest.Migration do
  @moduledoc false
  use Ecto.Migration
  def up, do: Chime.Migrations.up(version: 1)
  def down, do: Chime.Migrations.down(to: 0)
end

defmodule ChimeTest.ObanMigration do
  @moduledoc false
  use Ecto.Migration
  def up, do: Oban.Migration.up()
  def down, do: Oban.Migration.down()
end
