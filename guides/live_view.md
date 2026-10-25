# In LiveView

The bell, the feed and the preferences in your LiveViews.

## The hook

`Chime.Live` gives each LiveView of a `live_session` the `@chime` assign.
Put it after your own hooks, so that your resolver finds the user in the
socket's assigns:

```elixir
live_session :app,
  on_mount: [{MyAppWeb.UserAuth, :require_authenticated}, {Chime.Live, limit: 10}] do
  live "/stories", StoryLive.Index
end
```

`@chime` holds the person's counts and, while the panel is open, its
notifications. It is live: a notification that comes reaches every open
page of the person at once, and seeing or reading in one tab clears the
others. The news of one event to many people is one message to each node
of the cluster, which tells the pages there: no query for each person.

## The components

```heex
<div class="relative">
  <Chime.Components.bell chime={@chime} />
  <Chime.Components.feed chime={@chime} />
</div>
```

The bell shows a dot while the person has notifications they have not
seen, never a count, unless you ask (`count`). A click opens the feed,
which marks them seen. A click on a notification reads it and goes to its
`:url`; the feed has "Mark all as read", a filter of the unread, an
archive button on each, and "Show more".

The words are English, as attributes; give your own:

```heex
<Chime.Components.feed chime={@chime} title={gettext("Notifications")} empty={gettext("Nothing yet.")} />
```

The preferences, on a settings page:

```heex
<Chime.Components.preferences id="notifications" chime={@chime} labels={%{"email" => gettext("Email")}} />
```

## Your own markup

The events the components send are the hook's, and any element can send
them:

* `chime:toggle`, `chime:open`, `chime:close` - the panel; opening marks
  the feed seen.
* `chime:more` - the next page.
* `chime:filter` with `phx-value-filter="unread"` or `"inbox"`.
* `chime:read`, `chime:archive` with `phx-value-id`.
* `chime:read_all`.
* `chime:visit` with `phx-value-id` - reads it, and goes to its `:url`.

```heex
<button phx-click="chime:toggle">
  Inbox <span :if={@chime.unread > 0}>({@chime.unread})</span>
</button>

<ul :if={@chime.open}>
  <li :for={item <- @chime.items} phx-click="chime:visit" phx-value-id={item.id}>
    {item.feed.title}
  </li>
</ul>
```

`Chime.Live.State` has the fields of `@chime`.

## The style

The markup has classes of `chime-` and no style of its own. Chime's
style sheet is a start, with custom properties for the colours:

```css
@import "../../deps/chime/priv/static/chime.css";

:root {
  --chime-accent: theme(colors.orange.600);
}
```
