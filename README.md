# Chime

![Chime — Notifications for Phoenix](https://raw.githubusercontent.com/hattoriai/chime/main/media/banner.png)

Chime is notifications for Phoenix. Something happens in your app (a
comment, a payment that failed, a new follower), and Chime tells the
people it concerns: in the app's feed (the bell and its list), by email,
and by channels of your own, as each person wants. It gives your app:

* notifiers, a module for each kind of notification you have: who it goes
  to, by which channels, after how long, under which conditions, and what
  it says in each;
* a feed for each person, seen, read and archived, with counts kept as
  counts, never a `COUNT(*)` on a page;
* groups: "Ana and 4 others commented on Tokyo", one notification that
  comes back to the top, not five;
* actions on a notification ("Accept", "Decline"), and links of emails
  that read it in the feed when they are opened;
* push to browsers (Web Push), iPhones (APNs) and Android (FCM), each
  person's devices kept, those gone forgotten;
* Slack, Discord, Microsoft Teams, signed webhooks and SMS by Twilio;
* email through your Swoosh mailer, with one-click unsubscribe, and
  channels of your own (Telegram, SMS, Slack, push) in one behaviour;
* delays and fallbacks: in the feed now, by email in ten minutes unless
  it was read;
* preferences, a setting for each category and channel, required
  categories that cannot be turned off, and daily and weekly digests in
  each person's time zone;
* workspaces (teams, organisations), each with its feed, counts and
  preferences;
* a log of every decision, with its reason: why a person got an email,
  and why they did not;
* the bell and the feed in your LiveViews, live over PubSub, across tabs;
* a JSON API with a stream of server-sent events, for a frontend that
  Phoenix does not render (React, Vue, a mobile app);
* its words in your languages, through your own Gettext, and each
  email and digest in the person's language;
* `Chime.Test`, to assert what was notified and run the deliveries in
  your tests, with no Oban to drain and no clock to wait for.

Every delivery but the feed's is an Oban job, given to Oban in the same
transaction as the notification. Everything is in your database, on
PostgreSQL or SQLite.

## What Chime does

| | |
| --- | --- |
| Notifiers | `use Chime.Notifier`: a category, `deliver` for each channel with `:wait`, `:if` and `:unless`; `recipients/1`, `data/1`, `actor/1`, `group/1`; `feed/2`, `email/3`, and a function for each channel of yours |
| Events | `Chime.notify/3`: one event, each person once, an idempotency key; a batch of 1000 people at a time, the first in the event's transaction |
| Feed | each person's notifications, the latest first, pages, unread and archived filters; seen (the dot), read, archived; rendered when shown, in the person's language |
| Groups | a key and a window: the events of a group join the person's open notification, its count, its actors, its place at the top; a read closes it |
| Counts | `chime_counts`, one row a person, counted again only when their notifications change |
| Channels | the feed, email (Swoosh, `List-Unsubscribe` and one-click), and yours (`Chime.Channel`): `{:ok, ref}`, `{:skip, reason}`, `{:error, reason}` |
| Deliveries | Oban jobs at their time, in the notification's transaction; retried with Oban's backoff; the conditions and preferences decided at their time; a group's waiting email takes its later events |
| Preferences | categories in the config, with labels, defaults and `required`; a setting for each channel: on, off, daily or weekly |
| Digests | daily and weekly, at the hour of each person's time zone; your own email, or Chime's |
| The log | `Chime.explain/1`: the notification, each delivery, its status and reason: sent, skipped, waiting, digested, failed |
| In the app | `Chime.Live` and `Chime.Components`: the bell with a dot, the feed, the preferences; live over PubSub, one message a node for a batch of people |
| Any frontend | `chime_api`: the feed, the counts, the marks, the preferences, a stream of server-sent events, signed tokens (`Chime.Token`) |
| Unsubscribe | `chime_mail`: the link of each email, a page that asks first, and the one-click POST of mail clients |
| Testing | `Chime.Test`: `assert_notified/2`, `refute_notified/2`, `feed/2`, `deliver/1`, `run_digests/1`, `explain/1` |
| Database | PostgreSQL and SQLite, in a migration of your app (`Chime.Migrations`) |

## Install

Chime needs Elixir 1.18 or later (it uses the built-in `JSON` module),
Phoenix 1.7.14 or 1.8, Phoenix LiveView 1.1 or later, Oban 2.19 or
later, and Ecto with PostgreSQL or SQLite.

Add `{:chime, "~> 0.1"}` to your deps, write the migration of Chime's
tables, and run it:

```sh
mix chime.gen.migration
mix ecto.migrate
```

Start Chime in your supervision tree, after the repo, the PubSub and
Oban:

```elixir
{Chime,
 repo: MyApp.Repo,
 pubsub: MyApp.PubSub,
 resolver: MyApp.ChimeResolver,
 mailer: MyApp.Mailer,
 email_from: {"MyApp", "hello@myapp.com"},
 secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
 mail_url: "https://myapp.com/notifications/mail",
 categories: [
   comments: [label: "Comments on your stories"],
   followers: [label: "New followers", defaults: [email: :weekly]],
   billing: [label: "Billing", required: true]
 ]}
```

The [Quickstart](guides/quickstart.md) goes through it all.

## Use

Say who your people are:

```elixir
defmodule MyApp.ChimeResolver do
  @behaviour Chime.Resolver

  @impl true
  def recipient(%MyApp.User{} = user) do
    %Chime.Recipient{id: "user:#{user.id}", email: user.email, name: user.name, time_zone: user.time_zone}
  end

  @impl true
  def recipients(ids), do: ids |> MyApp.Accounts.users_by_chime_ids() |> Enum.map(&recipient/1)

  @impl true
  def resolve_recipient(%{assigns: %{current_scope: %{user: %MyApp.User{} = user}}}), do: recipient(user)
  def resolve_recipient(_nobody), do: nil
end
```

Write a notifier for each kind of notification:

```elixir
defmodule MyApp.Notifications.NewComment do
  use Chime.Notifier, category: :comments, group_window: {10, :minute}

  deliver :feed
  deliver :email, wait: {10, :minute}, unless: :read

  @impl true
  def recipients(%{comment: comment}), do: MyApp.Stories.followers(comment.story_id)

  @impl true
  def data(%{comment: c}), do: %{"story_id" => c.story_id, "story" => c.story.title, "text" => c.text}

  @impl true
  def actor(%{comment: c}), do: %{"id" => "user:#{c.author.id}", "name" => c.author.name}

  @impl true
  def group(%{comment: c}), do: "story:#{c.story_id}"

  @impl true
  def feed(data, notification) do
    %{title: "#{Chime.actors(notification)} commented on #{data["story"]}", body: data["text"], url: "/stories/#{data["story_id"]}"}
  end

  @impl true
  def email(data, _recipient, notification) do
    Swoosh.Email.new(subject: "#{Chime.actors(notification)} commented on #{data["story"]}", text_body: data["text"])
  end
end
```

and send one where it happens:

```elixir
Chime.notify(MyApp.Notifications.NewComment, %{comment: comment}, key: "comment:#{comment.id}")
```

Put the bell in your LiveViews: the hook in the `live_session`, after
your own, and the components in the layout:

```elixir
live_session :app, on_mount: [{MyAppWeb.UserAuth, :require_authenticated}, Chime.Live] do
  ...
end
```

```heex
<Chime.Components.bell chime={@chime} />
<Chime.Components.feed chime={@chime} />
```

For a frontend that Phoenix does not render, mount the API behind your
API's pipeline (see [Any frontend](guides/any_frontend.md)):

```elixir
import Chime.Router

scope "/api" do
  pipe_through :api_authenticated
  chime_api "/notifications"
end
```

And when someone asks why they never got an email:

```elixir
Chime.explain(notification_id) |> Chime.Explain.format() |> IO.puts()
```

```
2026-10-25 14:02:11Z  new_comment  to user:42  (comments)
2026-10-25 14:02:11Z  feed       shown
2026-10-25 14:05:40Z  feed       seen
2026-10-25 14:05:40Z  feed       read
2026-10-25 14:12:11Z  email      skipped     read in the feed at 2026-10-25 14:05:40Z
```

## Guides

* [Quickstart](guides/quickstart.md): from the dependency to the first notification in the bell.
* [Notifiers](guides/notifiers.md): recipients, data, groups, channels, delays and conditions.
* [Channels](guides/channels.md): the feed, email, and channels of your own.
* [Push](guides/push.md): browsers, iPhones and Android phones; the keys, devices, the service worker.
* [Preferences](guides/preferences.md): categories, settings, required notifications, digests, unsubscribe links.
* [Workspaces](guides/workspaces.md): teams, organisations, collectives: a feed, counts and preferences for each.
* [The log](guides/explain.md): what Chime decided, and why.
* [In LiveView](guides/live_view.md): the bell, the feed and the preferences.
* [Any frontend](guides/any_frontend.md): the JSON API, the stream, tokens, a React hook.
* [Languages](guides/languages.md): Chime's words through your Gettext.
* [Testing](guides/testing.md): `Chime.Test`.

## Development

```sh
mix deps.get
mix test        # on SQLite, and PostgreSQL when it is reachable
mix precommit
mix dialyzer
```

The PostgreSQL tests use `postgres:postgres@localhost/chime_test`, or
`CHIME_TEST_DATABASE_URL`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md): when a change needs an issue
first, and what a pull request needs. Report a security problem
privately, as [SECURITY.md](SECURITY.md) says.

## License

MIT, see `LICENSE`.
