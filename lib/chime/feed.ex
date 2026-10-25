defmodule Chime.Feed do
  @moduledoc """
  A person's feed: their notifications, the newest first, and what they
  did with them. `Chime` has the functions; the JSON API and `Chime.Live`
  are over them.

  A notification of the feed is shown by its notifier's `c:Chime.Notifier.feed/2`,
  when it is read: `render/1` gives `%{title:, body:, url:, icon:}`, and
  whatever else the notifier put in it.
  """

  import Ecto.Query

  alias Chime.{Config, Counts, Event, Fanout, Notification}

  @filters [:inbox, :unread, :archived, :all]

  @doc false
  @spec list(Config.t(), String.t(), keyword()) :: [Notification.t()]
  def list(%Config{} = config, recipient, opts) do
    limit = opts |> Keyword.get(:limit, 20) |> max(1)
    filter = Keyword.get(opts, :filter, :inbox)

    unless filter in @filters do
      raise ArgumentError, ":filter must be one of #{inspect(@filters)}, got: #{inspect(filter)}"
    end

    from(n in Notification,
      where: n.recipient == ^recipient and n.in_feed,
      order_by: [desc: n.updated_at, desc: n.id],
      limit: ^limit,
      preload: :event
    )
    |> filter(filter)
    |> in_workspace(opts[:workspace])
    |> before(config, recipient, opts[:before])
    |> config.repo.all(prefix: config.prefix)
  end

  defp filter(query, :inbox), do: where(query, [n], is_nil(n.archived_at))
  defp filter(query, :unread), do: where(query, [n], is_nil(n.archived_at) and is_nil(n.read_at))
  defp filter(query, :archived), do: where(query, [n], not is_nil(n.archived_at))
  defp filter(query, :all), do: query

  defp in_workspace(query, nil), do: query
  defp in_workspace(query, workspace), do: where(query, [n], n.workspace == ^workspace)

  # The page after a notification: those older than it, in the feed's
  # order. An id the person does not have gives the first page.
  defp before(query, _config, _recipient, nil), do: query

  defp before(query, config, recipient, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Notification{updated_at: at} <-
           config.repo.get_by(Notification, [id: id, recipient: recipient], prefix: config.prefix) do
      where(query, [n], n.updated_at < ^at or (n.updated_at == ^at and n.id < ^id))
    else
      _ -> query
    end
  end

  @doc """
  What the feed shows of a notification (its event preloaded): the
  notifier's `c:Chime.Notifier.feed/2`, with `:title` at least. A
  notifier no longer in the app shows its kind.
  """
  @spec render(Notification.t()) :: map()
  def render(%Notification{event: %Event{} = event} = notification) do
    case Event.notifier(event) do
      nil -> %{title: notification.kind}
      notifier -> render(notifier, event.data, notification)
    end
  end

  @doc false
  @spec render(module(), map(), Notification.t()) :: map()
  def render(notifier, data, notification) do
    if function_exported?(notifier, :feed, 2) do
      case notifier.feed(data, notification) do
        %{title: _} = feed ->
          feed

        other ->
          raise ArgumentError,
                "#{inspect(notifier)}.feed/2 must return a map with :title, got: #{inspect(other)}"
      end
    else
      %{title: notification.kind}
    end
  end

  @doc false
  # A notification as the JSON API gives it.
  @spec json(Notification.t()) :: map()
  def json(%Notification{} = n) do
    feed = render(n)
    {known, extra} = Map.split(feed, [:title, :body, :url, :icon, :actions])

    %{
      id: n.id,
      kind: n.kind,
      category: n.category,
      title: known[:title],
      body: known[:body],
      url: known[:url],
      icon: known[:icon],
      actions:
        for %{key: key} = a <- known[:actions] || [] do
          %{key: to_string(key), label: a[:label] || to_string(key)}
        end,
      action: n.action,
      actedAt: n.acted_at,
      clickedAt: n.clicked_at,
      extra: Map.new(extra, fn {k, v} -> {to_string(k), v} end),
      count: n.count,
      actors: n.actors,
      seen: n.seen_at != nil,
      read: n.read_at != nil,
      archived: n.archived_at != nil,
      seenAt: n.seen_at,
      readAt: n.read_at,
      archivedAt: n.archived_at,
      insertedAt: n.inserted_at,
      updatedAt: n.updated_at
    }
  end

  @doc false
  # Marks what a person has in the feed: seen, read, unread, archived,
  # unarchived, for these ids or :all, of a workspace or every one. Their
  # counts are counted again and told to their other pages. Returns the
  # counts, the whole feed's and each workspace's.
  @spec mark(Config.t(), String.t(), atom(), [String.t()] | :all, String.t() | nil) ::
          Counts.all()
  def mark(%Config{} = config, recipient, action, ids, workspace \\ nil) do
    now = DateTime.utc_now()

    query =
      from(n in Notification, where: n.recipient == ^recipient)
      |> only(ids)
      |> in_workspace(workspace)

    {:ok, counts} =
      config.repo.transaction(fn ->
        Counts.lock(config, [recipient])
        # Reading sees too, keeping the time of an earlier look; a click
        # reads.
        if action in [:read, :click], do: update(config, query, :seen, now)
        if action == :click, do: update(config, query, :read, now)
        update(config, query, action, now)
        Map.fetch!(Counts.refresh(config, [recipient]), recipient)
      end)

    Fanout.updated(config, recipient, counts)
    counts
  end

  defp update(config, query, action, now) do
    {query, set} = change(query, action, now)
    config.repo.update_all(query, [set: set], prefix: config.prefix)
  end

  defp only(query, :all), do: query

  defp only(query, ids) when is_list(ids) do
    ids = for id <- ids, {:ok, id} <- [Ecto.UUID.cast(id)], do: id
    where(query, [n], n.id in ^ids)
  end

  # Reading a notification sees it, and closes its group: the next event of
  # the group is a new notification, which the person has not read.
  defp change(query, :seen, now), do: {where(query, [n], is_nil(n.seen_at)), seen_at: now}

  defp change(query, :read, now) do
    {where(query, [n], is_nil(n.read_at)), read_at: now, grouping: false}
  end

  defp change(query, :click, now), do: {where(query, [n], is_nil(n.clicked_at)), clicked_at: now}

  defp change(query, :unread, _now), do: {where(query, [n], not is_nil(n.read_at)), read_at: nil}

  defp change(query, :archive, now),
    do: {where(query, [n], is_nil(n.archived_at)), archived_at: now, grouping: false}

  defp change(query, :unarchive, _now),
    do: {where(query, [n], not is_nil(n.archived_at)), archived_at: nil}
end
