defmodule Chime.Jobs do
  @moduledoc false
  # Every delivery but the feed is an Oban job of Chime.Worker, given to
  # Oban in the transaction that makes it: the delivery and its job are
  # kept together, or neither is. Two more jobs run by themselves, one in
  # the cluster each: the digests, every hour, and the cleanup of old
  # notifications, every day.

  alias Chime.Config

  require Logger

  @insert_chunk 500

  @doc false
  # The jobs of deliveries just made: [%{id:, scheduled_at:}].
  @spec deliveries(Config.t(), [map()]) :: :ok
  def deliveries(_config, []), do: :ok

  def deliveries(%Config{oban: oban}, rows) do
    check_queue(oban)

    rows
    |> Enum.map(fn %{id: id, scheduled_at: at} ->
      Chime.Worker.new(%{"job" => "deliver", "id" => id},
        queue: oban.queue,
        max_attempts: 5,
        scheduled_at: at
      )
    end)
    |> Enum.chunk_every(@insert_chunk)
    |> Enum.each(&Oban.insert_all(oban.name, &1))
  end

  @doc false
  # The job of a scheduled event, at its time.
  @spec notify(Config.t(), Ecto.UUID.t(), DateTime.t()) :: :ok
  def notify(%Config{oban: oban}, event_id, at) do
    check_queue(oban)

    {:ok, _job} =
      Oban.insert(
        oban.name,
        Chime.Worker.new(%{"job" => "notify", "id" => event_id},
          queue: oban.queue,
          max_attempts: 5,
          scheduled_at: at
        )
      )

    :ok
  end

  @doc false
  # At boot, on each node: the digests' job and the cleanup's, one each in
  # the cluster (unique).
  @spec boot(Config.t()) :: :ok
  def boot(%Config{oban: oban} = config) do
    check_queue(oban)
    now = DateTime.utc_now()
    schedule(oban, "digest", next_hour(now))
    if config.keep_days, do: schedule(oban, "cleanup", DateTime.add(now, 600))
    :ok
  rescue
    error ->
      Logger.error("Chime could not give Oban its jobs at boot: " <> Exception.message(error))
      :ok
  end

  @doc false
  @spec schedule(map(), String.t(), DateTime.t()) :: :ok
  def schedule(oban, job, at) do
    {:ok, _job} =
      Oban.insert(
        oban.name,
        Chime.Worker.new(%{"job" => job},
          queue: oban.queue,
          max_attempts: 3,
          scheduled_at: at,
          unique: [period: :infinity, keys: [:job], states: [:available, :scheduled, :retryable]]
        )
      )

    :ok
  end

  @doc false
  # The next hour, a few seconds past it.
  @spec next_hour(DateTime.t()) :: DateTime.t()
  def next_hour(now) do
    %{now | minute: 0, second: 5, microsecond: {0, 6}} |> DateTime.add(3600)
  end

  # A job in a queue the app does not run waits for ever: Chime says so,
  # once a node, rather than lose the deliveries without a word.
  defp check_queue(%{name: name, queue: queue}) do
    key = {__MODULE__, :checked, name, queue}

    unless :persistent_term.get(key, false) do
      oban = Oban.config(name)

      if oban.testing == :disabled and not Keyword.has_key?(oban.queues, queue) do
        Logger.error(
          "Chime gives its jobs to the #{inspect(queue)} queue of #{inspect(name)}, " <>
            "which does not run it: add it to the :queues of your Oban config, " <>
            "or give Chime another (oban: [name: #{inspect(name)}, queue: ...])"
        )
      end

      :persistent_term.put(key, true)
    end
  end
end
