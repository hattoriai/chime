defmodule Chime.Counts do
  @moduledoc false
  # Each person's counts of the feed, kept in chime_counts and counted
  # again only when the notifications change: a page reads one row, never
  # a COUNT of the notifications. A person has a row for the whole feed
  # (workspace ""), and one for each workspace they have notifications in.

  import Ecto.Query

  alias Chime.{Config, Count, Notification}

  @type counts :: %{unseen: non_neg_integer(), unread: non_neg_integer()}

  @typedoc "A person's counts: the whole feed's, and each workspace's."
  @type all :: %{
          unseen: non_neg_integer(),
          unread: non_neg_integer(),
          workspaces: %{String.t() => counts()}
        }

  @zero %{unseen: 0, unread: 0}

  @doc false
  # A person's counts: the whole feed's, or a workspace's.
  @spec get(Config.t(), String.t(), String.t() | nil) :: counts()
  def get(%Config{} = config, recipient, workspace \\ nil) do
    case config.repo.get_by(Count, [recipient: recipient, workspace: workspace || ""],
           prefix: config.prefix
         ) do
      %Count{unseen: unseen, unread: unread} -> %{unseen: unseen, unread: unread}
      nil -> @zero
    end
  end

  @doc false
  # The counts of a scope, from all of a person's counts.
  @spec scope(all(), String.t() | nil) :: counts()
  def scope(%{unseen: unseen, unread: unread}, nil), do: %{unseen: unseen, unread: unread}
  def scope(%{workspaces: workspaces}, workspace), do: Map.get(workspaces, workspace, @zero)

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
      ids
      |> Enum.sort()
      |> Enum.map(&%{recipient: &1, workspace: "", unseen: 0, unread: 0, updated_at: now})

    config.repo.insert_all(Count, rows,
      on_conflict: {:replace, [:updated_at]},
      conflict_target: [:recipient, :workspace],
      prefix: config.prefix
    )

    :ok
  end

  @doc false
  # Counts again the feed of these people, and keeps the counts:
  # %{recipient => all()}. A person with no notification left in the feed
  # counts zero; a workspace with none left has no row.
  @spec refresh(Config.t(), [String.t()]) :: %{String.t() => all()}
  def refresh(_config, []), do: %{}

  def refresh(%Config{} = config, ids) do
    now = DateTime.utc_now()

    base =
      from(n in Notification, where: n.recipient in ^ids and n.in_feed and is_nil(n.archived_at))

    whole =
      from(n in base,
        group_by: n.recipient,
        select: %{
          recipient: n.recipient,
          workspace: "",
          unseen: filter(count(n.id), is_nil(n.seen_at)),
          unread: filter(count(n.id), is_nil(n.read_at)),
          updated_at: type(^now, :utc_datetime_usec)
        }
      )

    by_workspace =
      from(n in base,
        where: not is_nil(n.workspace),
        group_by: [n.recipient, n.workspace],
        select: %{
          recipient: n.recipient,
          workspace: n.workspace,
          unseen: filter(count(n.id), is_nil(n.seen_at)),
          unread: filter(count(n.id), is_nil(n.read_at)),
          updated_at: type(^now, :utc_datetime_usec)
        }
      )

    # The workspaces' rows are made again: one with nothing left goes.
    from(c in Count, where: c.recipient in ^ids and c.workspace != "")
    |> config.repo.delete_all(prefix: config.prefix)

    rows =
      for query <- [whole, by_workspace],
          {_n, rows} = insert(config, query),
          row <- rows,
          do: row

    zeros =
      for id <- ids -- for(%{workspace: ""} = row <- rows, do: row.recipient),
          do: %{recipient: id, workspace: "", unseen: 0, unread: 0, updated_at: now}

    if zeros != [], do: insert(config, zeros)

    Enum.reduce(rows, Map.new(ids, &{&1, Map.put(@zero, :workspaces, %{})}), fn
      %{workspace: ""} = row, acc ->
        Map.update!(acc, row.recipient, &%{&1 | unseen: row.unseen, unread: row.unread})

      row, acc ->
        Map.update!(acc, row.recipient, fn all ->
          put_in(all, [:workspaces, row.workspace], %{unseen: row.unseen, unread: row.unread})
        end)
    end)
  end

  defp insert(config, source) do
    config.repo.insert_all(Count, source,
      on_conflict: {:replace, [:unseen, :unread, :updated_at]},
      conflict_target: [:recipient, :workspace],
      returning: [:recipient, :workspace, :unseen, :unread],
      prefix: config.prefix
    )
  end
end
