# Chime

![Chime — Notifications for Phoenix](https://raw.githubusercontent.com/hattoriai/chime/main/media/banner.png)

**Notifications for Phoenix: the bell in your app, the emails, the push
to phones, and a log that says why each one went or didn't.**

Someone comments on a story, a payment fails, a person is invited to a
team. You write a small module that says who should hear about it and
how. Chime puts it in their feed at once, sends the email ten minutes
later if they haven't seen it yet, and respects what each person chose
in their settings.

When someone asks "why did I never get that email?", you can look it up
and read the answer.

Everything lives in your own database, on PostgreSQL or SQLite. The
deliveries run as Oban jobs.

![The bell open in an app: a comment, three comments grouped into one, an invitation with Accept and Decline, and a failed payment](https://raw.githubusercontent.com/hattoriai/chime/main/media/bell.png)

## Install

You need Elixir 1.18+, Phoenix 1.7.14 or 1.8, Phoenix LiveView 1.1+ and
Oban 2.19+.

Add `{:chime, "~> 0.1"}` to the deps in `mix.exs`, then create Chime's
tables:

```sh
mix deps.get
mix chime.gen.migration
mix ecto.migrate
```

Start Chime in your application, after the repo, PubSub and Oban:

```elixir
{Chime,
 repo: MyApp.Repo,
 pubsub: MyApp.PubSub,
 resolver: MyApp.ChimeResolver,
 mailer: MyApp.Mailer,
 email_from: {"MyApp", "hello@myapp.com"}}
```

The resolver tells Chime who your users are. The
[Quickstart](guides/quickstart.md) shows one, and the rest of the setup.

## Your first notification

Write a notifier for each kind of notification:

```elixir
defmodule MyApp.Notifications.NewComment do
  use Chime.Notifier, category: :comments

  deliver :feed
  deliver :email, wait: {10, :minute}, unless: :read

  @impl true
  def recipients(%{comment: comment}), do: [comment.story.author]

  @impl true
  def data(%{comment: c}), do: %{"story" => c.story.title, "author" => c.author.name}

  @impl true
  def feed(data, _notification),
    do: %{title: "#{data["author"]} commented on #{data["story"]}"}

  @impl true
  def email(data, _recipient, _notification),
    do: Swoosh.Email.new(subject: "#{data["author"]} commented on #{data["story"]}")
end
```

Send it where the thing happens:

```elixir
Chime.notify(MyApp.Notifications.NewComment, %{comment: comment})
```

Show the bell in your layout:

```heex
<Chime.Components.bell chime={@chime} />
<Chime.Components.feed chime={@chime} />
```

The story's author sees it in the bell straight away. If they haven't
read it within ten minutes, they get the email too.

## What you get

* **A feed for each person.** Seen, read and archived, with live counts
  in every open tab. Three comments on one story become "Mei and 2
  others commented". → [Notifiers](guides/notifiers.md)
* **Every channel.** Email, push to browsers and phones, Slack, Discord,
  Teams, webhooks, SMS, or a channel of your own.
  → [Channels](guides/channels.md), [Push](guides/push.md)
* **People decide.** A setting for each kind of notification and each
  channel, daily and weekly digests, and a one-click unsubscribe in every
  email. → [Preferences](guides/preferences.md)
* **Good timing.** Wait before sending, send later, cancel, hold for
  quiet hours, and limit how many go out.
  → [Notifiers](guides/notifiers.md), [Channels](guides/channels.md)
* **Why, for each one.** Every delivery is logged with its reason, and
  an admin page lets you find a person, read their log, and send again
  what failed. → [The log](guides/explain.md), [The admin](guides/admin.md)
* **LiveView or React.** Ready-made components for LiveView, and a JSON
  API with a client and a React package for any other frontend.
  → [In LiveView](guides/live_view.md), [Any frontend](guides/any_frontend.md)
* **Teams and workspaces.** A separate feed and settings for each.
  → [Workspaces](guides/workspaces.md)
* **Your languages.** Chime's words go through your app's own Gettext.
  → [Languages](guides/languages.md)
* **Tests without waiting.** `Chime.Test` checks what was sent, with no
  jobs to drain and no clock to wait for. → [Testing](guides/testing.md)

The full list is in [Features](guides/features.md).

![The log of one notification: shown in the feed, seen three minutes later, and the email waiting for its time](https://raw.githubusercontent.com/hattoriai/chime/main/media/log.png)

## Try it

```sh
mix deps.get
mix dev
```

Open http://localhost:4100. It's a small app with a few notifications in
the bell, the admin at `/admin/notifications`, and a preview of each
notifier at `/admin/notifications/previews`.

## Guides

[Quickstart](guides/quickstart.md) ·
[Notifiers](guides/notifiers.md) ·
[Channels](guides/channels.md) ·
[Push](guides/push.md) ·
[Preferences](guides/preferences.md) ·
[Workspaces](guides/workspaces.md) ·
[The log](guides/explain.md) ·
[The admin](guides/admin.md) ·
[In LiveView](guides/live_view.md) ·
[Any frontend](guides/any_frontend.md) ·
[Languages](guides/languages.md) ·
[Testing](guides/testing.md) ·
[Features](guides/features.md)

## Development

```sh
mix deps.get
mix dev          # the development app at http://localhost:4100
mix test         # on SQLite, and on PostgreSQL when it is reachable
mix precommit    # the checks CI runs
```

The JavaScript lives in `assets/`; [CONTRIBUTING.md](CONTRIBUTING.md)
says how to build and test it, and what a pull request needs. Report
security problems privately, as [SECURITY.md](SECURITY.md) says.

## License

MIT. See `LICENSE`.
