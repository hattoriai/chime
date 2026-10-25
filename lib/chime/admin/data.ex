defmodule Chime.Admin.Data do
  @moduledoc false
  # What the admin's pages read.

  import Ecto.Query

  alias Chime.{Config, Delivery, Event, Notification}

  @doc false
  # The deliveries of the last day, by status.
  def statuses(%Config{} = config, now \\ DateTime.utc_now()) do
    since = DateTime.add(now, -1, :day)

    from(d in Delivery,
      where: d.updated_at > ^since,
      group_by: d.status,
      select: {d.status, count(d.id)}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Map.new()
  end

  @doc false
  def failed(%Config{} = config, limit \\ 20) do
    from(d in Delivery,
      where: d.status == "failed",
      order_by: [desc: d.updated_at],
      limit: ^limit,
      preload: [notification: :event]
    )
    |> config.repo.all(prefix: config.prefix)
  end

  @doc false
  def events(%Config{} = config, limit \\ 20) do
    from(e in Event, order_by: [desc: e.inserted_at], limit: ^limit)
    |> config.repo.all(prefix: config.prefix)
  end

  @doc false
  # A person's notifications, the latest first, in the feed or not, with
  # their deliveries.
  def notifications(%Config{} = config, recipient, limit \\ 50) do
    from(n in Notification,
      where: n.recipient == ^recipient,
      order_by: [desc: n.updated_at],
      limit: ^limit,
      preload: [:event, deliveries: ^from(d in Delivery, order_by: d.inserted_at)]
    )
    |> config.repo.all(prefix: config.prefix)
  end
end
