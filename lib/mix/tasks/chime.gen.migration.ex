defmodule Mix.Tasks.Chime.Gen.Migration do
  @shortdoc "Generates the migration that installs or upgrades Chime's tables"

  @moduledoc """
  Generates the migration of Chime's tables in the app's repo: the one
  that installs them, or, after an upgrade of Chime, the one that brings
  them to its latest version.

      $ mix chime.gen.migration
      $ mix chime.gen.migration --repo MyApp.Repo

  It is `mix phoenix_mountable.gen.migration Chime.Migrations`: the version
  the app is at is read from its migrations, and the new migration pins the
  latest (see `Chime.Migrations`). Run it with `mix ecto.migrate`.
  """

  use Mix.Task

  @impl Mix.Task
  def run(args), do: Mix.Task.run("phoenix_mountable.gen.migration", ["Chime.Migrations" | args])
end
