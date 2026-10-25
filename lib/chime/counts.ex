defmodule Chime.Counts do
  @moduledoc false
  # Each person's counts of the feed, kept in chime_counts and counted
  # again only when the notifications change: a page reads one row, never
  # a COUNT of the notifications.

  import Ecto.Query

  alias Chime.{Config, Count, Notification}

  @type counts :: %{unseen: non_neg_integer(), unread: non_neg_integer()}

  @doc false
  # A person's counts.
  @spec get(Config.t(), String.t()) :: counts()
  def get(%Config{} = config, recipient) do
    case config.repo.get(Count, recipient, prefix: config.prefix) do
      %Count{unseen: unseen, unread: unread} -> %{unseen: unseen, unread: unread}
      nil -> %{unseen: 0, unread: 0}
    end
  end

  @doc false
  # Locks the counts of these people for the transaction, in the order of
  # their ids, making the rows that are missing. On PostgreSQL, a second
  # transaction for the same people waits here until the first commits,
  # and its next statements see what the first wrote: the counts it then
  # counts are whole. SQLite has one writer at a time.
  @spec lock(Config.t(), [String.t()]) :: :ok
  def lock(_config, []), do: :ok

  def lock(%Config{} = config, ids) do
    now = DateTime.utc_now()

    rows =
      ids |> Enum.sort() |> Enum.map(&%{recipient: &1, unseen: 0, unread: 0, updated_at: now})

    config.repo.insert_all(Count, rows,
      on_conflict: {:replace, [:updated_at]},
      conflict_target: :recipient,
      prefix: config.prefix
    )

    :ok
  end

  @doc false
  # Counts again the feed of these people, in one statement, and keeps the
  # counts: %{recipient => counts}. A person with no notification left in
  # the feed counts zero.
  @spec refresh(Config.t(), [String.t()]) :: %{String.t() => counts()}
  def refresh(_config, []), do: %{}

  def refresh(%Config{} = config, ids) do
    now = DateTime.utc_now()

    query =
      from(n in Notification,
        where: n.recipient in ^ids and n.in_feed and is_nil(n.archived_at),
        group_by: n.recipient,
        select: %{
          recipient: n.recipient,
          unseen: filter(count(n.id), is_nil(n.seen_at)),
          unread: filter(count(n.id), is_nil(n.read_at)),
          updated_at: type(^now, :utc_datetime_usec)
        }
      )

    {_n, rows} =
      config.repo.insert_all(Count, query,
        on_conflict: {:replace, [:unseen, :unread, :updated_at]},
        conflict_target: :recipient,
        returning: [:recipient, :unseen, :unread],
        prefix: config.prefix
      )

    counted = Map.new(rows, &{&1.recipient, %{unseen: &1.unseen, unread: &1.unread}})

    case ids -- Map.keys(counted) do
      [] ->
        counted

      empty ->
        zeros = Enum.map(empty, &%{recipient: &1, unseen: 0, unread: 0, updated_at: now})

        config.repo.insert_all(
          Count,
          zeros,
          on_conflict: {:replace, [:unseen, :unread, :updated_at]},
          conflict_target: :recipient,
          prefix: config.prefix
        )

        Map.merge(counted, Map.new(empty, &{&1, %{unseen: 0, unread: 0}}))
    end
  end
end
