# The admin

A page for you, not your people: the deliveries of the last day by
status, the ones that failed and a button to send them again, the latest
events, each person's notifications with their deliveries, preferences
and devices, and each notification's log.

## Mounting it

```elixir
import Chime.Router

scope "/admin" do
  pipe_through [:browser, :require_admin]

  chime_admin "/notifications",
    access: MyAppWeb.ChimeAdminAccess,
    on_mount: [{MyAppWeb.AdminAuth, :require_admin}]
end
```

```elixir
defmodule MyAppWeb.ChimeAdminAccess do
  @behaviour Chime.Admin.Access

  @impl true
  def allow?(conn), do: match?(%MyApp.Admin{}, conn.assigns[:current_admin])
end
```

`:access` is required: Chime asks it on the request of each page, after
your pipeline, and the admin is a 404 to anyone it does not allow. Keep
your admin pipeline and `on_mount` in front of it all the same.

The admin is a page of its own, with its own small style sheet and
script, served under the mount: your app needs no asset of it. Its
LiveViews use your app's LiveView socket.

## What it has

* **The first page** - the deliveries of the last day by status, the
  ones that failed with their error and "Send again", and the latest
  events with their counts of people, status and key. The search goes to
  a person by their id.
* **A person** - their counts, their notifications with each delivery's
  status (its reason on hover), their preferences and their devices.
* **A notification** - what it says, its log (`Chime.explain/1`), its
  deliveries with "Send again" for those that failed or were skipped, and
  its data.

"Send again" is `Chime.resend/1`: the delivery is scheduled now, its
attempts from nought, and what is decided at its time (the preferences,
the conditions, the rules) is decided again.
