defmodule Chime.Cleanup do
  @moduledoc false
  # The notifications older than :keep_days, with their deliveries, and
  # the events no notification points to any more, a batch at a time; the
  # counts of the people whose feed lost some, counted again.

  import Ecto.Query

  alias Chime.{Config, Counts, Event, Notification}

  @batch 1000

  @doc false
  @spec run(Config.t(), DateTime.t()) :: :ok
  def run(%Config{keep_days: nil}, _now), do: :ok

  def run(%Config{} = config, now) do
    cutoff = DateTime.add(now, -config.keep_days, :day)
    notifications(config, cutoff)
    events(config, cutoff)
    :ok
  end

  defp notifications(config, cutoff) do
    rows =
      from(n in Notification,
        where: n.updated_at < ^cutoff,
        limit: @batch,
        select: {n.id, n.recipient}
      )
      |> config.repo.all(prefix: config.prefix)

    if rows != [] do
      ids = Enum.map(rows, &elem(&1, 0))
      config.repo.delete_all(from(n in Notification, where: n.id in ^ids), prefix: config.prefix)
      Counts.refresh(config, rows |> Enum.map(&elem(&1, 1)) |> Enum.uniq())
      if length(rows) == @batch, do: notifications(config, cutoff)
    end
  end

  defp events(config, cutoff) do
    ids =
      from(e in Event,
        as: :event,
        where: e.inserted_at < ^cutoff,
        where: not exists(from(n in Notification, where: n.event_id == parent_as(:event).id)),
        limit: @batch,
        select: e.id
      )
      |> config.repo.all(prefix: config.prefix)

    if ids != [] do
      config.repo.delete_all(from(e in Event, where: e.id in ^ids), prefix: config.prefix)
      if length(ids) == @batch, do: events(config, cutoff)
    end
  end
end
