# Workspaces

A workspace is a part of your app that a person can be in: a team, an
organisation, a collective, a project. A notification can be of one, and
then the feed, its counts and the preferences can be a workspace's.
Without workspaces, nothing changes: every notification is of the whole
feed.

## A notification's workspace

A notifier says it with `workspace/1`:

```elixir
defmodule MyApp.Notifications.NewComment do
  use Chime.Notifier, category: :comments

  @impl true
  def workspace(%{comment: comment}), do: "collective:#{comment.story.collective_id}"
  ...
end
```

or `Chime.notify/3` with `:workspace`, which comes first:

```elixir
Chime.notify(MyApp.Notifications.Invited, %{invite: invite}, workspace: "collective:#{invite.collective_id}")
```

A workspace is a string of yours, as the people's ids are.

## The feed of a workspace

Everything that reads the feed takes it:

```elixir
Chime.feed("user:42", workspace: "collective:7")
Chime.counts("user:42", workspace: "collective:7")
Chime.mark_seen("user:42", workspace: "collective:7")
Chime.mark_read("user:42", :all, workspace: "collective:7")
```

Without `:workspace`, the whole feed: every workspace's notifications,
and those of none. Each person's counts are kept for the whole feed and
for each workspace, so either is one row.

A group is a workspace's own: comments on the same story in two
workspaces are two notifications.

## In LiveView and the JSON API

The resolver says the workspace of a page or a request:

```elixir
@impl true
def resolve_workspace(%{assigns: %{current_collective: %{id: id}}}), do: "collective:#{id}"
def resolve_workspace(_whole_app), do: nil
```

`Chime.Live` and the JSON API are then that workspace's: the bell's dot,
the feed, "Mark all as read", the preferences. A notification of another
workspace still reaches the page, and leaves its dot as it is. The API
also takes `?workspace=` for a request, before the resolver's: a person
only ever has their own notifications, in any workspace.

## Preferences

A person's settings are for every workspace. A setting in a workspace
(`workspace:`) comes before them, there only:

```elixir
Chime.put_preference("user:42", :comments, :email, :off)
Chime.put_preference("user:42", :comments, :email, :daily, workspace: "collective:7")
```

The person gets no comment emails, but a daily digest of those of
collective 7. In a workspace, `Chime.preferences/2` gives its own setting
where the person made one, else theirs for all.

A link to unsubscribe turns the emails of its category off in every
workspace: the workspaces' own settings of it go.

## Branding

A notifier's `email/3` has the notification, and its `workspace`: write
the email in the workspace's name and colours from there.
