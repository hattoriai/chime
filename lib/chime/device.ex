defmodule Chime.Device do
  @moduledoc """
  A person's device, for the `:push` channel:

    * `:kind` - `"web"` (a browser's Web Push subscription), `"apns"` (an
      iPhone's or a Mac's token) or `"fcm"` (an Android phone's token, or
      any app's of Firebase);
    * `:token` - the subscription's endpoint, or the token;
    * `:keys` - a Web Push subscription's `"p256dh"` and `"auth"`;
    * `:name` - what the person calls it ("Ana's iPhone"), or nil;
    * `:enabled` - whether it gets notifications: a person turns a device
      off and on, and keeps it;
    * `:last_used_at` - when a push last went to it.

  A device a service says is gone (an unsubscribed browser, an app
  removed) is deleted, and the log says so.
  """

  use Chime.Schema

  @kinds ~w(web apns fcm)

  schema "chime_devices" do
    field :recipient, :string
    field :kind, :string
    field :token, :string
    field :keys, :map
    field :name, :string
    field :enabled, :boolean, default: true
    field :last_used_at, :utc_datetime_usec
    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc false
  def kinds, do: @kinds
end
