defmodule Chime.Message do
  @moduledoc """
  A notification on its way to a person by a channel, as
  `c:Chime.Channel.deliver/2` gets it:

    * `:channel` - the channel's name (`"telegram"`);
    * `:notifier` - the notifier's module; `:kind` and `:category`;
    * `:data` - the notifier's data of the latest event (`c:Chime.Notifier.data/1`);
    * `:recipient` - the `Chime.Recipient`, as the resolver gives them now;
    * `:notification` - the `Chime.Notification`, with its count and
      actors;
    * `:required` - whether it goes whatever the preferences (the
      channel then leaves out any way to unsubscribe).
  """

  @enforce_keys [:channel, :notifier, :data, :recipient, :notification]
  defstruct [
    :channel,
    :notifier,
    :kind,
    :category,
    :data,
    :recipient,
    :notification,
    required: false
  ]

  @type t :: %__MODULE__{
          channel: String.t(),
          notifier: module(),
          kind: String.t(),
          category: String.t(),
          data: map(),
          recipient: Chime.Recipient.t(),
          notification: Chime.Notification.t(),
          required: boolean()
        }

  @doc """
  What the notifier says by the message's channel: the function of the
  notifier named after the channel, `(data, recipient, notification)`,
  when it has one (`telegram/3` for `"telegram"`), else what the feed
  shows (`c:Chime.Notifier.feed/2`).
  """
  @spec render(t()) :: term()
  def render(%__MODULE__{notifier: notifier} = message) do
    fun = String.to_existing_atom(message.channel)

    if function_exported?(notifier, fun, 3) do
      apply(notifier, fun, [message.data, message.recipient, message.notification])
    else
      Chime.Feed.render(notifier, message.data, message.notification)
    end
  end
end
