# Push

Notifications on people's devices: browsers by Web Push, iPhones and Macs
by Apple's APNs, Android phones by Firebase Cloud Messaging (FCM). Chime
keeps each person's devices, sends to each one that is on, and forgets
those a service says are gone.

## The keys

Each service needs keys of your app's. Keep them as secrets, read in
`config/runtime.exs`.

| Service | What | Where |
| --- | --- | --- |
| Web Push | a pair of **VAPID keys** and a contact address | `mix chime.gen.vapid`, once: browsers subscribed with the public key stop getting pushes if it changes |
| APNs | a **.p8 key**, its **Key ID**, your **Team ID**, your app's **bundle ID** | Apple Developer → Certificates, Identifiers & Profiles → Keys → a key with "Apple Push Notifications service"; the Team ID is in Membership |
| FCM | a **service account** JSON | Firebase console → Project settings → Service accounts → Generate new private key |

```elixir
# config/runtime.exs
config :my_app, :chime_push,
  web: [
    public_key: System.fetch_env!("VAPID_PUBLIC_KEY"),
    private_key: System.fetch_env!("VAPID_PRIVATE_KEY"),
    subject: "mailto:ops@myapp.com"
  ],
  apns: [
    key: System.fetch_env!("APNS_KEY"),
    key_id: System.fetch_env!("APNS_KEY_ID"),
    team_id: System.fetch_env!("APNS_TEAM_ID"),
    topic: "com.myapp.ios",
    env: :production
  ],
  fcm: [service_account: System.fetch_env!("FIREBASE_SERVICE_ACCOUNT")]
```

```elixir
{Chime, ..., push: Application.fetch_env!(:my_app, :chime_push)}
```

Give only the services you use. With `:push`, the `:push` channel is
there, and in the preferences. Chime sends with `Req`: add
`{:req, "~> 0.5"}` to your deps.

## A notifier

```elixir
deliver :push, unless: :seen

def push(data, _recipient, notification) do
  %{
    title: "#{Chime.actors(notification)} commented",
    body: data["text"],
    url: "/stories/#{data["story_id"]}",
    icon: "/images/icon-192.png",
    badge: "/images/badge-72.png",
    image: data["cover_url"]
  }
end
```

Without `push/3`, a push says what the feed says. Chime adds the link
that reads the notification in the feed when the push is opened
(`Chime.link/2`), and the notification's group as its tag: a newer push
of the group replaces the one on the device (the tag of Web Push and
Android, with `renotify`, and APNs' collapse id and thread). The delivery
rules work as for email: `throttle:`, quiet hours, limits.

## Browsers

Serve Chime's service worker from your root, and register it:

```elixir
# endpoint.ex: /chime-sw.js from deps/chime/priv/static
plug Plug.Static, at: "/", from: {:chime, "priv/static"}, only: ~w(chime-sw.js)
```

Then, in your page, ask for permission and send the subscription to the
JSON API (`chime_api`):

```js
const api = "/api/v1/notifications";

export async function enablePush() {
  const { vapidPublicKey } = await (await fetch(`${api}/push`)).json();
  const registration = await navigator.serviceWorker.register("/chime-sw.js");
  if ((await Notification.requestPermission()) !== "granted") return;

  const subscription = await registration.pushManager.subscribe({
    userVisibleOnly: true,
    applicationServerKey: vapidPublicKey,
  });

  const { endpoint, keys } = subscription.toJSON();
  await fetch(`${api}/devices`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-csrf-token": csrfToken },
    body: JSON.stringify({ kind: "web", token: endpoint, keys, name: navigator.userAgent }),
  });
}
```

`chime-sw.js` shows each push and opens its link on a click. An app with
a service worker of its own copies its two listeners.

## Phones

Your iOS or Android app gets a token from Apple or Firebase, and sends it
to the API, signed in as the person:

```http
POST /api/v1/notifications/devices
Content-Type: application/json

{"kind": "apns", "token": "<the device token, hex>", "name": "Ana's iPhone"}
```

`"fcm"` for Firebase's tokens (Android, or iOS through Firebase). A token
registered again, by another person, is that person's device now.

## Devices

`GET /devices`, `PATCH /devices/:id` with `{"enabled": false}` (the
device kept, its pushes off) or `{"name": ...}`, `DELETE /devices/:id`;
and `Chime.devices/1`, `Chime.register_device/2`,
`Chime.update_device/3`, `Chime.remove_device/2` on the server.

A push goes to every device of the person that is on. A device the
service says is gone (an unsubscribed browser, 404 or 410; an app removed
from a phone, APNs' 410 or `BadDeviceToken`; FCM's `UNREGISTERED`) is
forgotten. The log says how many devices it reached and which were gone:

```
2026-10-25 14:02:11Z  push       sent        1 of 2 devices; 1 gone, forgotten: the app is no longer on the device (410)
```

A push that reaches no device because each failed is tried again, as any
delivery.
