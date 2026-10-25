# Preferences

What each person wants to hear about: a setting for each category and
each channel.

## Categories

The config names the categories, in the order the preferences show them:

```elixir
categories: [
  comments: [label: "Comments", description: "On your stories"],
  followers: [label: "New followers", defaults: [email: :weekly]],
  mentions: [label: "Mentions", defaults: [email: :on, telegram: :off]],
  billing: [label: "Billing", required: true]
]
```

* `:label` and `:description` - what the person reads.
* `:defaults` - the setting of each channel for a person who has not
  changed it: `:on`, `:off`, and for email `:daily` or `:weekly`. A
  channel not named is `:on`.
* `:required` - its notifications go whatever the settings, and their
  emails have no link to unsubscribe: receipts, security, the account.
  Its settings cannot be changed.

Every notifier has a category of the config. Without `:categories`, any
category is taken, with every channel on, and the preferences show none.

## Settings

| Setting | |
| --- | --- |
| `"on"` | it goes |
| `"off"` | it does not, and the log says when the person turned it off |
| `"daily"`, `"weekly"` | email only: it waits for the person's digest |

```elixir
Chime.preferences("user:42")
#=> [%{category: %{key: "comments", label: "Comments", ...}, settings: %{"feed" => "on", "email" => "daily"}}, ...]

Chime.put_preference("user:42", :comments, :email, :daily)
#=> :ok
Chime.put_preference("user:42", :billing, :email, :off)
#=> {:error, :required}
```

The feed turned off for a category keeps its notifications out of the
feed and its counts; its other channels still go.

A setting is read when each delivery goes, so a person who turns email
off now gets none of the emails that wait.

## The forms

* In LiveView: `<Chime.Components.preferences id="notifications" chime={@chime} />`,
  a table with a choice for each category and channel, kept as it
  changes.
* In any frontend: `GET` and `PUT /preferences` of `chime_api` (see
  [Any frontend](any_frontend.md)).

## Digests

A category's email set to `"daily"` or `"weekly"` does not go at its
time: its delivery waits, as `"digest"`, with the rest decided (the
conditions of the notifier, the person's other settings). Every hour, a
job finds the people whose digest is due, in their own time zone (the
recipient's `:time_zone`, UTC without one): at the config's hour, every
day for daily, on its day for weekly.

```elixir
{Chime, ..., digest: [at: 9, weekly_on: :monday, email: MyApp.ChimeDigest]}
```

The time zones need a time zone database, set as Elixir's:

```elixir
config :elixir, :time_zone_database, Tz.TimeZoneDatabase
```

The digest's email is Chime's (a list of the notifications as the feed
shows them, with links whole from the config's `:url`), or your module's
`email(recipient, items, period)`; see `Chime.Digest`. It carries a link
that turns off every email but the required.

## Unsubscribing

Each email has a link to turn off its category's emails, and the headers
of one-click unsubscribe; the digest's turns off every email. Mount the
page at the config's `:unsubscribe_url`:

```elixir
pipeline :unsubscribe do
  plug :accepts, ["html"]
end

scope "/" do
  pipe_through :unsubscribe
  chime_unsubscribe "/notifications/unsubscribe", app_name: "MyApp"
end
```

A `GET` asks first, with a button: mail clients and scanners open links,
and must not unsubscribe anyone. A `POST`, the button's or a mail
client's one-click, turns the emails off. The link is signed with the
config's `:secret_key_base`, and does not expire.
