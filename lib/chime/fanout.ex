defmodule Chime.Fanout do
  @moduledoc false
  # The live news of a notification, to each person's open pages, with no
  # query for each: one message to each node for a batch of people, and
  # each node's fanout tells the people's topics there (a local
  # broadcast, which finds no one when they have no page open on it).

  use GenServer

  alias Chime.Config

  @topic "chime:fanout"

  @doc false
  def start_link(%Config{} = config),
    do: GenServer.start_link(__MODULE__, config, name: __MODULE__)

  @doc false
  # Tells the people of a batch, with their counts: %{recipient => counts}.
  @spec notified(Config.t(), %{String.t() => map()}) :: :ok
  def notified(_config, counts) when counts == %{}, do: :ok

  def notified(%Config{} = config, counts) do
    Phoenix.PubSub.broadcast(config.pubsub, @topic, {__MODULE__, :notified, counts})
  end

  @doc false
  # Tells one person's pages, on every node, that their feed changed: they
  # saw it or read it in another tab.
  @spec updated(Config.t(), String.t(), map()) :: :ok
  def updated(%Config{} = config, recipient, counts) do
    Phoenix.PubSub.broadcast(config.pubsub, Chime.topic(recipient), {Chime, :updated, counts})
  end

  @impl GenServer
  def init(config) do
    :ok = Phoenix.PubSub.subscribe(config.pubsub, @topic)
    {:ok, config}
  end

  @impl GenServer
  def handle_info({__MODULE__, :notified, counts}, config) do
    for {recipient, counts} <- counts do
      Phoenix.PubSub.local_broadcast(
        config.pubsub,
        Chime.topic(recipient),
        {Chime, :notified, counts}
      )
    end

    {:noreply, config}
  end

  def handle_info(_message, config), do: {:noreply, config}
end
