defmodule Chime.Event do
  @moduledoc """
  Something that happened, once, whoever it notifies: a call of
  `Chime.notify/3`. Its notifications point to it.

    * `:notifier` - the module that made it; `:kind` - its name, as the
      JSON API and the components give it (`"new_comment"`).
    * `:category` - the category of `Chime.Config` it is of.
    * `:data` - what the notifier's `data/1` kept of the params, as JSON:
      the feed and the emails are made from it when they are shown.
    * `:workspace` - the workspace it happened in, or nil.
    * `:actor` - who did it (`%{"id" => ..., "name" => ...}`), or nil.
    * `:group_key` - the group its notifications join, or nil.
    * `:key` - the idempotency key it was given, or nil: a second call
      with the same key does nothing.
    * `:recipients` - how many people it notified.
    * `:status` - `"sent"`; `"scheduled"` until its time, `:scheduled_at`
      (`Chime.notify/3` with `:at`), its people kept in `:audience`; or
      `"cancelled"` before it (`Chime.cancel/2`); `"sending"` while the
      jobs of an audience (`c:Chime.Notifier.audience/1`) go through it,
      `:cursor` the key of the last person done.
  """

  use Chime.Schema

  schema "chime_events" do
    field :notifier, :string
    field :kind, :string
    field :category, :string
    field :data, :map, default: %{}
    field :actor, :map
    field :workspace, :string
    field :group_key, :string
    field :key, :string
    field :recipients, :integer, default: 0
    field :status, :string, default: "sent"
    field :scheduled_at, :utc_datetime_usec
    field :audience, {:array, :string}
    field :cursor, :string
    field :inserted_at, :utc_datetime_usec
  end

  @type t :: %__MODULE__{}

  @doc false
  # The notifier module, from its name, if it is still loaded.
  @spec notifier(t()) :: module() | nil
  def notifier(%__MODULE__{notifier: name}) do
    module = Module.concat([name])
    if Code.ensure_loaded?(module) and function_exported?(module, :__chime__, 1), do: module
  end
end
