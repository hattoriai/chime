# Backlog

Known gaps in Chime, each to become an issue.

## Web Push and phones

Push is a channel of the app's own today. Chime would keep each
person's devices (a `chime_devices` table: Web Push subscriptions, APNs
and FCM tokens), register them through the JSON API, send with
`web_push` or `pushx`, and forget a device its service says is gone.

## Replies by email, with Letterbox

An email of a notification with a `Reply-To` of a signed address
(`reply+<token>@in.myapp.com`), and a handler of Letterbox that checks
the token and gives the app the notification, the person and the text
of the reply, without the quoted message. An optional module, compiled
when the app has Letterbox.

## An admin

A page, mounted behind the app's admin pipeline, to find a person's
notifications and read their log (`Chime.explain/1`), and to see the
deliveries that fail.

## Words in the app's languages

The components' words are English attributes, and `Chime.actors/1`
speaks English. A `Chime.Messages` with the languages of Tayori's, as
Tayori has, and Gettext for the digest's email.

## Many people at once

`Chime.notify/3` takes a list of people and works it 1000 at a time, in
the caller's process. An event to everyone would rather take an Ecto
query of the app's and work it in jobs, each batch its own job.

## The mail provider's events

The `ref` of an email is the provider's id. Its webhooks (a bounce, a
complaint, a delivery) could mark the delivery and stop writing to an
address that bounces, as Tayori's campaigns do.

## An installer

`mix igniter.install chime`: the dependency, the migration, the child in
the application, a resolver to fill in, the mounts and the hook.

## The stream on many nodes

`GET /stream` holds a connection for each open page. On a server that
closes idle connections, the client reconnects (as `EventSource` does);
the guide could say how long a proxy should keep them.
