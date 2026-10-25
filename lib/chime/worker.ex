defmodule Chime.Worker do
  @moduledoc false
  # Chime's Oban jobs: a delivery, the digests of the hour, the cleanup.

  use Oban.Worker

  alias Chime.{Cleanup, Config, Deliver, Digest, Jobs}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job" => "deliver", "id" => id}} = job) do
    Deliver.perform(Config.get(), id, job.attempt >= job.max_attempts)
  end

  def perform(%Oban.Job{args: %{"job" => "digest"}}) do
    config = Config.get()
    now = DateTime.utc_now()
    Digest.run(config, now)
    Jobs.schedule(config.oban, "digest", Jobs.next_hour(now))
  end

  def perform(%Oban.Job{args: %{"job" => "cleanup"}}) do
    config = Config.get()
    now = DateTime.utc_now()
    Cleanup.run(config, now)
    Jobs.schedule(config.oban, "cleanup", DateTime.add(now, 1, :day))
  end
end
