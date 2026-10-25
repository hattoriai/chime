defmodule Chime.Notification do
  @moduledoc """
  What a person was told of an event: an item of their feed, and what the
  other channels' deliveries hang from.

    * `:recipient` - the id of the person.
    * `:event` - the latest event of it; `:kind` and `:category` are its.
    * `:workspace` - the workspace it is of, or nil (see `Chime.notify/3`).
    * `:count` - how many events it holds: 1, or more when the events of a
      group joined it ("Ana and 4 others commented"); `:actors` - who did
      them, the latest first, up to 20 (`%{"id", "name"}`);
      `:actor_count` - how many different people did them.
    * `:in_feed` - whether the feed shows it: false when the person turned
      the feed off for the category, while other channels still go.
    * `:seen_at` - when the person saw it in the feed (the bell's dot);
      `:read_at` - when they read it (opened it, or marked it read);
      `:archived_at` - when they put it away; `:clicked_at` - when they
      opened it from a link of an email or a channel (`Chime.link/2`);
      `:action` and `:acted_at` - the action they took on it, and when
      (`Chime.act/3`).
    * `:updated_at` - when an event last joined it: the feed is in this
      order, so that a group with a new event comes up.
  """

  use Chime.Schema

  schema "chime_notifications" do
    field :recipient, :string
    belongs_to :event, Chime.Event
    field :kind, :string
    field :category, :string
    field :workspace, :string
    field :group_key, :string
    field :grouping, :boolean, default: false
    field :grouped_until, :utc_datetime_usec
    field :count, :integer, default: 1
    field :actors, {:array, :map}, default: []
    field :actor_count, :integer, default: 0
    field :in_feed, :boolean, default: true
    field :seen_at, :utc_datetime_usec
    field :read_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    field :clicked_at, :utc_datetime_usec
    field :action, :string
    field :acted_at, :utc_datetime_usec
    has_many :deliveries, Chime.Delivery
    timestamps()
  end

  @type t :: %__MODULE__{}
end
