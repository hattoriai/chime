# The log

Chime writes down every decision it makes about a notification, with the
reason, so that you can answer "why?" later.

## Why it matters

Chime chooses not to send many things, on purpose:

* the person turned email off for the category;
* they read the notification in the feed before its email's time;
* they have no address, or left;
* the notifier's condition said no.

All of it is right, and from the outside it looks the same as a bug: "I
never got the email." Without a log, you go through your logs, Oban's
jobs and your mail provider, and often still cannot tell "Chime chose
not to" from "something broke". With it, you look:

```elixir
Chime.explain(notification_id) |> Chime.Explain.format() |> IO.puts()
```

```
2026-10-25 14:02:11Z  new_comment  to user:42  (comments)
2026-10-25 14:02:11Z  feed       shown
2026-10-25 14:02:11Z  telegram   skipped     if telegram? was false
2026-10-25 14:05:40Z  feed       seen
2026-10-25 14:05:40Z  feed       read
2026-10-25 14:12:11Z  email      skipped     read in the feed at 2026-10-25 14:05:40Z
```

## What it holds

The notification's own steps: it came (in the feed, or not, when the
person turned the feed off), the events of its group that joined it,
when it was seen, read, archived. And each delivery, as
`Chime.Delivery` keeps it:

| Status | Reason |
| --- | --- |
| `scheduled` | waits until its time |
| `sent` | the channel's ref (the mail provider's id) |
| `skipped` | the person turned the channel off, and when; read or seen in the feed; a condition of the notifier; no address; the resolver no longer gives the person; the channel's own reason |
| `digest` | waits for the person's daily or weekly digest |
| `digested` | went in the digest |
| `failed` | the channel's last error, after Oban's last attempt |

`Chime.explain/1` gives it as data (`%{notification:, steps: [%{at:,
channel:, status:, reason:}]}`), for a page of your admin.

## How long

The log is the notification's: it is kept as long as it is, the config's
`:keep_days` (180) after its last event, then a daily job removes both.
