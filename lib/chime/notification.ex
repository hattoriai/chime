defmodule Chime.Notification do
  @moduledoc """
  What a person was told of an event: an item of their feed, and what the
  other channels' deliveries hang from.

    * `:recipient` - the id of the person.
    * `:event` - the latest event of it; `:kind` and `:category` are its.
    * `:count` - how many events it holds: 1, or more when the events of a
      group joined it ("Ana and 4 others commented"); `:actors` - who did
      them, the latest first, up to 5 (`%{"id", "name"}`).
    * `:in_feed` - whether the feed shows it: false when the person turned
      the feed off for the category, while other channels still go.
    * `:seen_at` - when the person saw it in the feed (the bell's dot);
      `:read_at` - when they read it (opened it, or marked it read);
      `:archived_at` - when they put it away.
    * `:updated_at` - when an event last joined it: the feed is in this
      order, so that a group with a new event comes up.
  """

  use Chime.Schema

  schema "chime_notifications" do
    field :recipient, :string
    belongs_to :event, Chime.Event
    field :kind, :string
    field :category, :string
    field :group_key, :string
    field :grouping, :boolean, default: false
    field :grouped_until, :utc_datetime_usec
    field :count, :integer, default: 1
    field :actors, {:array, :map}, default: []
    field :in_feed, :boolean, default: true
    field :seen_at, :utc_datetime_usec
    field :read_at, :utc_datetime_usec
    field :archived_at, :utc_datetime_usec
    has_many :deliveries, Chime.Delivery
    timestamps()
  end

  @type t :: %__MODULE__{}
end
