defmodule Chime.Count do
  @moduledoc false
  # A person's counts of the feed, kept as counts: the notifications they
  # have not seen (the dot) and have not read, of those not archived.

  use Ecto.Schema

  @primary_key false
  schema "chime_counts" do
    field :recipient, :string, primary_key: true
    # "" for the whole feed, else a workspace's part of it.
    field :workspace, :string, primary_key: true, default: ""
    field :unseen, :integer, default: 0
    field :unread, :integer, default: 0
    field :updated_at, :utc_datetime_usec
  end
end
