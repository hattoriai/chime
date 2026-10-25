# Any frontend

The feed and the preferences as JSON, with a stream of what happens, for
a frontend that Phoenix does not render: React, Vue, Svelte, a mobile
app. The same notifications, counts and preferences as the LiveView
components, from the same tables.

## The mount

Mount it behind your API's pipeline, the one that knows who is signed
in: your session, or your API's own bearer token.

```elixir
import Chime.Router

scope "/api/v1" do
  pipe_through :api_authenticated
  chime_api "/notifications"
end
```

The resolver reads the person from the conn, after your pipeline:

```elixir
def resolve_recipient(%Plug.Conn{assigns: %{current_user: %User{} = user}}), do: recipient(user)
```

A request with no person is a 401. `Chime.API` has every route and the
JSON of a notification.

| Route | |
| --- | --- |
| `GET /` | the feed: `notifications`, `more`, `unseen`, `unread`; `?before=<id>`, `?limit=`, `?filter=unread\|archived\|all` |
| any | `?workspace=`: the routes are that workspace's, as the resolver's `resolve_workspace/1` makes them |
| `GET /counts` | `{"unseen": n, "unread": n}` |
| `POST /seen` | the dot goes |
| `POST /read` | all read |
| `POST /:id/read`, `/unread`, `/archive`, `/unarchive` | one |
| `POST /:id/actions/:action` | an action of its `actions` (`Chime.act/3`): the counts, `action` and `url` |
| `GET /preferences`, `PUT /preferences` | the settings |
| `GET /stream` | server-sent events |
| `POST /token` | a token of `Chime.Token` |

Each `POST` answers with the counts. Behind `protect_from_forgery`, it
needs the session's CSRF token in `x-csrf-token`.

## The stream

`GET /stream` is the person's live news as server-sent events: `counts`
at once, `notified` when a notification comes, `updated` when they see
or read in another tab, each with the counts. An `EventSource` cannot
send an `authorization` header: on the same origin, it sends your
session's cookie; with a bearer token of your API, ask the API for a
token of Chime's (`POST /token`, valid for a day) and give it as
`?token=`.

## The client

Chime ships its client of this API, with its types: `createChime`, in
`chime.js`. Phoenix's esbuild finds it in `deps`, as it finds Phoenix's
own JavaScript:

```js
import { createChime } from "chime";

const chime = createChime({ api: "/api/v1/notifications" });

const { notifications, unseen } = await chime.feed({ limit: 20 });
await chime.markRead(notifications[0].id);

const stop = chime.subscribe((event, counts) => console.log(event, counts));
```

A frontend of its own repository installs it from the Hex package's
directory or from Git:

```sh
npm install ../my_app/deps/chime
```

* `api` - where `chime_api` is mounted.
* `token` - a bearer, or a function that gives one, for a page of
  another origin (see [Tokens](#tokens)). Without it, the session's
  cookie, with the page's `<meta name="csrf-token">` on each `POST`.
* `workspace` - the workspace of every request.

It has a function for each route below: `feed`, `counts`, `markSeen`,
`readAll`, `markRead`, `markUnread`, `archive`, `unarchive`, `act`,
`preferences`, `setPreferences`, `devices`, `registerDevice`,
`updateDevice`, `removeDevice`, and `enableWebPush`, which asks the
browser and registers it (see [Push](push.md)). A failed request throws a
`ChimeError`, with the status and the API's `error`.

`subscribe` opens the stream, and gives each event with the counts. With
a bearer, it first takes a token of Chime's for the stream's address, as
an `EventSource` sends no headers.

## React

`chime/react` has a provider, hooks over the client, and a bell with its
feed, in the classes of `chime.css`:

```tsx
import { ChimeProvider, NotificationBell } from "chime/react";
import "chime/chime.css";

export function Header() {
  return (
    <ChimeProvider api="/api/v1/notifications" token={() => auth.token()}>
      <NotificationBell onNavigate={(url) => navigate(url)} />
    </ChimeProvider>
  );
}
```

React stays the app's: the package names it as a peer.

* `useNotifications({limit, filter})` - the feed and the counts, kept as
  the stream tells, with `markSeen`, `markRead`, `readAll`, `archive`,
  `act`, `loadMore` and `setFilter`.
* `useCounts()` - the counts alone, for a dot or a badge.
* `usePreferences()` - the preferences, and `set(category, channel,
  setting)`.
* `useChime()` - the provider's client.
* `Bell` and `NotificationBell` - the bell, and the bell with its feed.
  `words` gives their text in the person's language.

A bell of your own design uses the hooks:

```tsx
function Bell() {
  const { counts, items, markSeen, markRead } = useNotifications({ limit: 10 });
  const [open, setOpen] = useState(false);

  return (
    <div className="relative">
      <button aria-label="Notifications" onClick={() => { setOpen(!open); if (!open) markSeen(); }}>
        <BellIcon />
        {counts.unseen > 0 && <span className="dot" />}
      </button>
      {open && (
        <ul>
          {items.map((n) => (
            <li key={n.id} className={n.read ? "" : "unread"}>
              <a href={n.url ?? "#"} onClick={() => markRead(n.id)}>{n.title}</a>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
```

## The preferences

```http
GET /api/v1/notifications/preferences
```

```json
{
  "categories": [
    {"key": "comments", "label": "Comments", "description": "On your stories", "required": false,
     "settings": {"feed": "on", "email": "daily"}},
    {"key": "billing", "label": "Billing", "description": null, "required": true,
     "settings": {"feed": "on", "email": "on"}}
  ],
  "channels": [
    {"key": "feed", "settings": ["on", "off"]},
    {"key": "email", "settings": ["on", "daily", "weekly", "off"]}
  ]
}
```

```http
PUT /api/v1/notifications/preferences
Content-Type: application/json

{"preferences": {"comments": {"email": "weekly"}}}
```

A change that cannot be made (a required category, an unknown category
or channel, a setting the channel does not have) is a 422 with
`{"error", "category", "channel"}`, and none of the request's changes is
kept.

## Tokens

`Chime.Token.sign/1` signs a person's id with the config's
`:secret_key_base`, for a day. Make one on the server, for the person
the page is for, never from an id the browser sends; the API takes it as
`Bearer <token>`, and `/stream` as `?token=` too. `POST /token` makes one for the person of
the request. The mount's `:token_max_age` changes how long they last:

```elixir
chime_api "/notifications", token_max_age: 3600
```

## A mobile app

The same API, with your app's bearer token. Push to phones is a channel
of your own today (`Chime.Channel`): Pigeon or another library in its
`deliver/2`.
