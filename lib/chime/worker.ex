defmodule Chime.Worker do
  @moduledoc false
  # Chime's Oban jobs: a delivery, the digests of the hour, the cleanup.

  use Oban.Worker

  alias Chime.{Cleanup, Config, Deliver, Digest, Jobs}

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"job" => "deliver", "id" => id}} = job) do
    Deliver.perform(Config.get(), id, job.attempt >= job.max_attempts)
  end

  def perform(%Oban.Job{args: %{"job" => "notify", "id" => id}}) do
    Chime.Notify.fire(Config.get(), id)
  end

  def perform(%Oban.Job{args: %{"job" => "audience", "id" => id} = args}) do
    Chime.Notify.page(Config.get(), id, args["cursor"])
  end

  def perform(%Oban.Job{args: %{"job" => "digest"}}) do
    config = Config.get()
    now = DateTime.utc_now()
    # The next first: a run that fails does not stop the ones after.
    Jobs.schedule(config.oban, "digest", Jobs.next_hour(now))
    Digest.run(config, now)
  end

  def perform(%Oban.Job{args: %{"job" => "cleanup"}}) do
    config = Config.get()
    now = DateTime.utc_now()
    Jobs.schedule(config.oban, "cleanup", DateTime.add(now, 1, :day))
    Cleanup.run(config, now)
  end
end
