defmodule Chime.Schema do
  @moduledoc false
  # The schemas of Chime's tables: ids made by Chime, times in UTC to the
  # microsecond.

  defmacro __using__(_opts) do
    quote do
      use Ecto.Schema
      @primary_key {:id, :binary_id, autogenerate: true}
      @foreign_key_type :binary_id
      @timestamps_opts [type: :utc_datetime_usec]
    end
  end

  @doc false
  # A time as the tables keep it, to the microsecond.
  @spec usec(DateTime.t()) :: DateTime.t()
  def usec(%DateTime{microsecond: {us, _}} = at), do: %{at | microsecond: {us, 6}}
end
