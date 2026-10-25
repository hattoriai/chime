defmodule Chime.WorkerTest do
  use ChimeTest.DataCase

  import Chime.Test

  for_each_repo do
    test "a delivery's job delivers it, and does nothing the second time", %{oban: oban} do
      ana = person!(1, telegram: "chat")
      {:ok, _} = comment!(ana)
      [%Delivery{id: id}] = deliveries(ana, channel: :telegram)
      job = %Oban.Job{args: %{"job" => "deliver", "id" => id}, attempt: 1, max_attempts: 5}

      assert :ok = Chime.Worker.perform(job)
      assert_received {:telegram, "chat", _}
      assert :ok = Chime.Worker.perform(job)
      refute_received {:telegram, _, _}
      _ = oban
    end

    test "a failed attempt is an error for Oban to retry, and the last one fails it" do
      ana = person!(1, telegram: "fails")
      {:ok, _} = comment!(ana)
      [%Delivery{id: id}] = deliveries(ana, channel: :telegram)

      assert {:error, :timeout} =
               Chime.Worker.perform(%Oban.Job{
                 args: %{"job" => "deliver", "id" => id},
                 attempt: 1,
                 max_attempts: 2
               })

      assert [%Delivery{status: "scheduled"}] = deliveries(ana, channel: :telegram)

      ExUnit.CaptureLog.capture_log(fn ->
        assert {:error, :timeout} =
                 Chime.Worker.perform(%Oban.Job{
                   args: %{"job" => "deliver", "id" => id},
                   attempt: 2,
                   max_attempts: 2
                 })
      end)

      assert [%Delivery{status: "failed"}] = deliveries(ana, channel: :telegram)
    end

    test "the digests' job and the cleanup's schedule the next", %{repo: repo} do
      assert :ok = Chime.Worker.perform(%Oban.Job{args: %{"job" => "digest"}})
      assert :ok = Chime.Worker.perform(%Oban.Job{args: %{"job" => "cleanup"}})

      assert ["cleanup", "digest"] =
               Oban.Job |> repo.all() |> Enum.map(& &1.args["job"]) |> Enum.sort()

      assert :ok = Chime.Jobs.boot(Chime.Config.get())
      assert 2 = repo.aggregate(Oban.Job, :count)
    end
  end
end
