defmodule Chime.Preference do
  @moduledoc false
  # A person's setting of a channel for a category: "on", "off", or, for
  # email, "daily" or "weekly". A setting not kept is the category's
  # default (Chime.Config).

  use Ecto.Schema

  @primary_key false
  schema "chime_preferences" do
    field :recipient, :string, primary_key: true
    field :category, :string, primary_key: true
    field :channel, :string, primary_key: true
    field :setting, :string
    field :updated_at, :utc_datetime_usec
  end
end
