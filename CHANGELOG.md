# Changelog

All notable changes to Chime are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Chime follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Notifiers (`Chime.Notifier`): a category, `deliver` for each channel
  with `:wait`, `:if` and `:unless`; `recipients/1`, `data/1`, `actor/1`,
  `group/1`, `feed/2`, `email/3`, and a function for each of the app's
  channels.
- `Chime.notify/3`: one event, each person once, an idempotency key, in
  batches of 1000 people.
- The feed: seen, read, archived, pages and filters; counts kept in
  `chime_counts`; groups of events in one notification.
- Channels: the feed, email through the app's Swoosh mailer with
  one-click unsubscribe, and the app's own (`Chime.Channel`). Each
  delivery but the feed's is an Oban job, in the notification's
  transaction.
- Preferences: categories with labels, defaults and `required`; a
  setting for each channel; daily and weekly digests in each person's
  time zone (`Chime.Digest`).
- The log: `Chime.explain/1` and `Chime.Explain.format/1`, every
  decision with its reason.
- `Chime.Live` and `Chime.Components`: the bell, the feed and the
  preferences in LiveView, live over PubSub.
- `chime_api`: the feed and the preferences as JSON, a stream of
  server-sent events, and tokens (`Chime.Token`); `chime_unsubscribe`, the
  page of the links to unsubscribe.
- Chime's words in the app's languages, through the app's own Gettext
  (`:gettext`, `Chime.Messages`), from the template
  `priv/gettext/chime.pot`; deliveries and digests in each person's
  locale, the notifiers' own words with them.
- Workspaces: a notification of a team or an organisation of the app's
  (`workspace/1` of the notifier, or `:workspace`); the feed, the counts,
  the marks and the preferences of a workspace; the resolver's
  `resolve_workspace/1` for `Chime.Live` and the JSON API, which also
  takes `?workspace=`.
- Guards: the notifier's `notify?/2`, checked for each person when the
  notification comes; `:if` and `:unless` on the feed; the actor left
  out of the recipients unless `notify_actor: true`; a notification kept
  out of the feed has a `"feed"` delivery with the reason, for the log.
  A base module of the app's for its notifiers, in the Notifiers guide.
- Scheduled notifications (`Chime.notify/3` with `:at`), and
  `Chime.cancel/2`: a scheduled event not sent, a sent one's waiting
  deliveries skipped, and with `feed: :remove` its notifications out of
  the feeds. `Chime.Test.run_scheduled/1`.
- Delivery rules: `throttle:` (one by a channel for a group in a time),
  `debounce:` and `max_wait:` (a quick run of a group's events as one),
  quiet hours (`:quiet_hours` of the config and of each recipient, and
  `quiet: false` on a channel) and limits of a channel by person
  (`:limits`). A held delivery waits for its new time, and the log says
  why.
- `Chime.Test`, and `mix chime.gen.migration` (`Chime.Migrations`, on
  PostgreSQL and SQLite).
