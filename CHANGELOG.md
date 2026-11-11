# Changelog

All notable changes to Chime are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and Chime follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## 0.3.0 (2026-11-11)

### Added

- `Chime.LiveActivity`: an iPhone's Live Activity, changed
  (`update/3`) or ended (`finish/3`) from the server, by APNs'
  `liveactivity` push with the config's `:apns` keys. An app can end an
  activity when the phone cannot. See the [Push](guides/push.md#live-activities)
  guide.

## 0.2.0 (2026-11-10)

### Added

- A push for a phone's app: the notifier's `push/3` takes `:category`
  (APNs' `category`, the actions the app registered),
  `:interruption_level` (`:passive`, `:active`, `:time_sensitive` or
  `:critical`; APNs' `interruption-level`, Web Push's urgency) and
  `:data`, a map of the app's own (the ids its actions need), at the top
  of APNs' payload, in FCM's data and in Web Push's message. See the
  [Push](guides/push.md) guide.

### Changed

- An APNs push with a `:category` is `mutable-content` too, as one with
  an `:image` was: the app's notification service extension runs for it.
- `deliver :push` is skipped while the config has no `:push`: an app can
  declare its pushes before it has the keys (its development, its tests),
  where it raised an `ArgumentError` before.

## 0.1.0 (2026-11-03)

The first release.

### Added

- `Chime.Components.preferences/1` takes a `:setting` slot: the app draws
  each channel's control (its own picker) in place of a `<select>`. The
  slot gets the control's `:id`, `:name`, `:value`, `:options`,
  `:disabled` and `:label`; the form's change saves it, as before.
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
  server-sent events, and tokens (`Chime.Token`); `chime_mail`, the
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
- Audiences: a notifier's `audience/1`, a query of the app's, gone
  through in Oban jobs 1000 people a page, each page once, for an
  announcement to everyone; `recipient_id/1`, `audience_key:`,
  `Chime.Test.run_audiences/0`.
- Actions: `actions` in `feed/2`, the notifier's `act/3`, `Chime.act/3`,
  the feed's buttons in LiveView and `POST /:id/actions/:action`.
- Read everywhere: `Chime.link/2`, a signed link that reads the
  notification when it is opened, then redirects; the email's
  `assigns.link`, and the digests' links, at `/open/:token` of
  `chime_mail`.
- Push: the `:push` channel, to browsers by Web Push (RFC 8291 and
  8292), Apple's devices by APNs and Android's by FCM, with the keys of
  the config's `:push`; each person's devices (`chime_devices`, turned on
  and off, forgotten when a service says they are gone), registered by
  the JSON API (`/devices`, `/push`); the notifier's `push/3`; the group
  as the tag that replaces a push on the device; `priv/static/chime-sw.js`;
  `mix chime.gen.vapid`.
- Channels over HTTP: `Chime.Channels.Slack` (a bot's `chat.postMessage`,
  or an incoming webhook), `Chime.Channels.Discord`, `Chime.Channels.Teams`
  (an Adaptive Card), `Chime.Channels.Webhook` (JSON, signed with HMAC)
  and `Chime.Channels.Twilio` (SMS); a person's address from their data,
  or one for everyone.
- The admin, `chime_admin` with the app's `Chime.Admin.Access`: the
  deliveries of the last day, the failed and "Send again"
  (`Chime.resend/1`), the events, each person, each notification's log.
- Previews: the notifier's `preview/0`, and the admin's `/previews`, each
  notifier as its channels say it, alone and as a group.
- The client of the JSON API, `chime.js` (`createChime`), and its React
  package, `chime/react`: `ChimeProvider`, `useNotifications`,
  `useCounts`, `usePreferences`, `Bell` and `NotificationBell`, with
  their types.
- `Chime.Test`, and `mix chime.gen.migration` (`Chime.Migrations`, on
  PostgreSQL and SQLite).
