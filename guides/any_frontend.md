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

## A React hook

```tsx
import { useCallback, useEffect, useState } from "react";

type Counts = { unseen: number; unread: number };

type Notification = {
  id: string;
  kind: string;
  title: string;
  body: string | null;
  url: string | null;
  count: number;
  actors: { id: string; name: string }[];
  read: boolean;
  updatedAt: string;
};

const api = "/api/v1/notifications";

async function call<T>(path: string, init?: RequestInit): Promise<T> {
  const response = await fetch(api + path, { credentials: "same-origin", ...init });
  if (!response.ok) throw new Error(`${response.status}`);
  return response.json();
}

export function useNotifications() {
  const [counts, setCounts] = useState<Counts>({ unseen: 0, unread: 0 });
  const [items, setItems] = useState<Notification[]>([]);
  const [more, setMore] = useState(false);

  const load = useCallback(async () => {
    const page = await call<{ notifications: Notification[]; more: boolean } & Counts>("?limit=20");
    setItems(page.notifications);
    setMore(page.more);
    setCounts({ unseen: page.unseen, unread: page.unread });
  }, []);

  useEffect(() => {
    load();
    const stream = new EventSource(api + "/stream");
    stream.addEventListener("counts", (e) => setCounts(JSON.parse(e.data)));
    stream.addEventListener("updated", (e) => setCounts(JSON.parse(e.data)));
    stream.addEventListener("notified", (e) => {
      setCounts(JSON.parse(e.data));
      load();
    });
    return () => stream.close();
  }, [load]);

  const post = (path: string) => call<Counts>(path, { method: "POST" }).then(setCounts);

  return {
    counts,
    items,
    more,
    markSeen: () => post("/seen"),
    markRead: (id: string) => post(`/${id}/read`).then(load),
    markAllRead: () => post("/read").then(load),
    archive: (id: string) => post(`/${id}/archive`).then(load),
  };
}
```

```tsx
function Bell() {
  const { counts, items, markSeen, markRead } = useNotifications();
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
