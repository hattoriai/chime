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
- `Chime.Test`, and `mix chime.gen.migration` (`Chime.Migrations`, on
  PostgreSQL and SQLite).
