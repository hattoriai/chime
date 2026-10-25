defmodule Chime.Delivery do
  @moduledoc """
  A notification by a channel other than the feed, and what became of it:
  the log `Chime.Explain` reads.

    * `:channel` - `"email"`, or one of the app's channels.
    * `:status`:
        * `"scheduled"` - waits for its time (`:scheduled_at`), and a job;
        * `"sent"` - the channel took it; `:ref` is the channel's id of
          it, such as the mail provider's;
        * `"skipped"` - Chime chose not to send it, and `:reason` says
          why: the person turned it off, read it already, has no address;
        * `"digest"` - waits for the person's daily or weekly digest;
        * `"digested"` - went in a digest (`:ref` is the digest's id);
        * `"failed"` - the channel failed on every attempt, and `:reason`
          is its last error.
    * `:attempts` - how many times the channel was tried.
  """

  use Chime.Schema

  @statuses ~w(scheduled sent skipped digest digested failed)

  schema "chime_deliveries" do
    belongs_to :notification, Chime.Notification
    field :recipient, :string
    field :channel, :string
    field :status, :string, default: "scheduled"
    field :reason, :string
    field :ref, :string
    field :attempts, :integer, default: 0
    field :scheduled_at, :utc_datetime_usec
    timestamps()
  end

  @type t :: %__MODULE__{}

  @doc false
  def statuses, do: @statuses
end
