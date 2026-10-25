defmodule Chime.Actions do
  @moduledoc false
  # The actions of a notification (Chime.act/3): what the feed offers,
  # the notifier's act/3, then the notification read with the action kept.

  alias Chime.{Config, Event, Feed, Notification}

  import Ecto.Query

  @doc false
  @spec act(Config.t(), String.t(), Ecto.UUID.t(), String.t()) ::
          {:ok, %{action: String.t(), url: String.t() | nil}} | {:error, term()}
  def act(config, recipient, id, action) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Notification{} = n <-
           config.repo.one(
             from(n in Notification,
               where: n.id == ^id and n.recipient == ^recipient,
               preload: :event
             ),
             prefix: config.prefix
           ),
         nil <- n.action,
         notifier when notifier != nil <- Event.notifier(n.event),
         true <- action in keys(Feed.render(n)) || {:error, :unknown_action},
         {:ok, url} <- call(notifier, action, n) do
      now = DateTime.utc_now()

      from(x in Notification, where: x.id == ^id and is_nil(x.action))
      |> config.repo.update_all([set: [action: action, acted_at: now]], prefix: config.prefix)

      Feed.mark(config, recipient, :read, [id])
      {:ok, %{action: action, url: url}}
    else
      :error -> {:error, :not_found}
      nil -> {:error, :not_found}
      action when is_binary(action) -> {:error, :already}
      {:error, reason} -> {:error, reason}
    end
  end

  # The keys of the actions a feed offers.
  defp keys(feed), do: for(%{key: key} <- Map.get(feed, :actions, []), do: to_string(key))

  defp call(notifier, action, notification) do
    unless function_exported?(notifier, :act, 3) do
      raise ArgumentError, "#{inspect(notifier)} offers actions in feed/2, and has no act/3"
    end

    case notifier.act(action, notification.event.data, notification) do
      :ok -> {:ok, nil}
      {:ok, url} when is_binary(url) -> {:ok, url}
      {:error, reason} -> {:error, reason}
    end
  end
end
