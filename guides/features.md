# Features

Everything Chime does, in one table. Each guide tells more.

| | |
| --- | --- |
| Notifiers | a module for each kind of notification (`use Chime.Notifier`): its category, the people it goes to, its data, and what it says on each channel; `deliver` for each channel, with `:wait`, `:if` and `:unless`; guards (`notify?/2`) and the actor left out of their own notifications; a base module for all your notifiers |
| Sending | `Chime.notify/3`, in your own transaction or not; each person once, and an idempotency key against doubles; later (`at:`) and cancelled (`Chime.cancel/2`); to everyone, or to a query of thousands, in pages of 1000 in Oban jobs |
| The feed | each person's notifications, the latest first, in pages; seen (the dot), read, archived and unarchived; filters for unread and archived; read in one place, read everywhere |
| Groups | a key and a window: "Mei and 2 others commented on Tokyo", one notification that comes back to the top with its count and its people, not three |
| Actions | buttons on a notification ("Accept", "Decline"), handled by the notifier, and the result kept |
| Counts | the unseen and unread of each person and workspace, kept in a row of their own and correct under parallel writes, never counted on a page |
| Email | through your Swoosh mailer; one-click unsubscribe (RFC 8058) and a link in the footer; a link that opens the notification and reads it in the feed |
| Push | browsers (Web Push, with its service worker), iPhones (APNs) and Android (FCM); each person's devices, turned on and off, and the ones gone forgotten; `mix chime.gen.vapid` |
| Other channels | Slack, Discord, Microsoft Teams, signed webhooks and SMS by Twilio, built in; your own (`Chime.Channel`), with `{:ok, ref}`, `{:skip, reason}` and `{:error, reason}` |
| Timing | a wait before a channel, and a fallback ("by email in ten minutes unless read"); debounce and a longest wait; a throttle for each group; quiet hours in each person's time zone; limits for each channel |
| Preferences | the categories in your config, with labels, descriptions and defaults; a setting for each category and channel: on, off, daily or weekly; required categories that can't be turned off |
| Digests | daily and weekly emails at the hour of each person's time zone, Chime's or your own |
| Workspaces | teams, organisations, collectives: a feed, counts and preferences for each, and a brand for their emails |
| The log | every decision with its reason, from shown and seen to sent, skipped, waiting, digested and failed (`Chime.explain/1`) |
| The admin | `chime_admin` behind your own access check: the last day, what failed and sending it again, the events, each person and each notification's log |
| Previews | each notifier as each of its channels says it, alone and as a group, from the notifier's `preview/0` |
| In LiveView | `Chime.Live` and `Chime.Components`: the bell, the feed and the preferences, live over PubSub, across tabs |
| Any frontend | `chime_api`: the JSON API, a stream of server-sent events, and signed tokens for another origin or a mobile app; `chime.js` and its React package, `chime/react`, with their types |
| Languages | Chime's words through your app's Gettext, with no translations to ship; each email and digest in the person's language |
| Testing | `Chime.Test`: `assert_notified/2`, `refute_notified/2`, the feed, the deliveries run at once, the digests, the log |
| Database | PostgreSQL and SQLite, in a migration of your app (`Chime.Migrations`); everything in your database, every delivery but the feed's an Oban job |
