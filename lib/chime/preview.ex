defmodule Chime.Preview do
  @moduledoc false
  # A notifier rendered with its preview/0's params, as each of its
  # channels would say it, to a person of the preview, with no database:
  # alone, and as a group of three when it has groups.

  alias Chime.{Event, Feed, Message, Notification, Recipient}

  @doc false
  # The notifiers with previews: the app's, or those loaded.
  @spec notifiers(atom() | nil) :: [module()]
  def notifiers(otp_app) do
    modules =
      case otp_app && Application.spec(otp_app, :modules) do
        modules when is_list(modules) -> modules
        _ -> for {module, _} <- :code.all_loaded(), do: module
      end

    modules
    |> Enum.filter(&(Chime.Notifier.notifier?(&1) and function_exported?(&1, :preview, 0)))
    |> Enum.sort()
  end

  @doc false
  # The examples of a notifier: [{name, params}].
  @spec examples(module()) :: [{String.t(), term()}]
  def examples(notifier) do
    case notifier.preview() do
      [{name, _} | _] = examples when is_binary(name) -> examples
      params -> [{"Example", params}]
    end
  end

  @doc false
  # What each channel says of an example.
  @spec render(module(), term()) :: map()
  def render(notifier, params) do
    data = notifier.data(params)
    actor = notifier.actor(params)
    recipient = %Recipient{id: "preview", name: "Ana Preview", email: "ana@example.com"}
    one = notification(notifier, data, actor, 1)
    channels = Enum.map(notifier.__chime__(:deliveries), & &1.channel)

    %{
      data: data,
      channels: channels,
      feed: "feed" in channels && Feed.render(notifier, data, one),
      group:
        notifier.group(params) && "feed" in channels &&
          Feed.render(notifier, data, notification(notifier, data, actor, 3)),
      email:
        "email" in channels && function_exported?(notifier, :email, 3) &&
          email(notifier, data, recipient, one),
      others:
        for channel <- channels, channel not in ["feed", "email"] do
          message = %Message{
            channel: channel,
            notifier: notifier,
            kind: notifier.__chime__(:kind),
            category: to_string(notifier.__chime__(:category)),
            data: data,
            recipient: recipient,
            notification: one
          }

          {channel, safe(fn -> Message.render(message) end)}
        end
    }
  end

  defp notification(notifier, data, actor, count) do
    now = DateTime.utc_now()

    others =
      for {name, i} <- Enum.with_index(["Rui", "Kenji"], 2),
          do: %{"id" => "preview:#{i}", "name" => name}

    actors = if actor, do: [actor | Enum.take(others, count - 1)], else: []

    %Notification{
      id: "00000000-0000-0000-0000-000000000000",
      recipient: "preview",
      kind: notifier.__chime__(:kind),
      category: notifier.__chime__(:category),
      count: count,
      actors: actors,
      actor_count: length(actors),
      inserted_at: now,
      updated_at: now,
      event: %Event{data: data, kind: notifier.__chime__(:kind), notifier: inspect(notifier)}
    }
  end

  defp email(notifier, data, recipient, notification) do
    safe(fn -> notifier.email(data, recipient, notification) end)
  end

  # A preview that raises shows the error, not a crash of the page.
  defp safe(fun) do
    fun.()
  rescue
    error -> {:error, Exception.message(error)}
  end
end
