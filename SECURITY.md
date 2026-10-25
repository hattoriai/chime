# Security

## Reporting a vulnerability

Do not open a public issue for a security problem. Report it privately
through GitHub: [Report a vulnerability](https://github.com/hattoriai/chime/security/advisories/new).

Say what an attacker can do, and how: the mount (the JSON API, its
stream, the page to unsubscribe) or the LiveView events, the request or
the payload, and the steps. We answer within a week, agree on a fix and
a date, and credit you in the advisory unless you ask us not to.

## Supported versions

Security fixes are made to the latest release. Chime is before 1.0, so
a fix is not backported to an earlier minor version.

## What is in scope

Chime runs in your app, behind your pipelines and your resolver, and
takes requests that any person can craft: the JSON API and its stream,
the links to unsubscribe, and the events of the LiveView hook. A problem
is in scope when such a request can:

- read, mark or archive another person's notifications, or read or
  change their preferences;
- forge a token of `Chime.Token` or a link to unsubscribe, or use a
  token past its life;
- run a script in the bell, the feed or the preferences, from the words
  of a notification;
- crash the app, or make the server or the database do unbounded work.

Who a person is, is decided by your resolver and your pipelines: those
are the app's job. What a notifier says, and who it goes to, is the
app's code.
