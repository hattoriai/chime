# Notifiers

A notifier is a kind of notification of your app, in a module of its
own: who it goes to, by which channels, after how long, under which
conditions, and what it says in each. Chime has none of its own: every
app has its own kinds, so you write one for each.

```elixir
defmodule MyApp.Notifications.NewComment do
  use Chime.Notifier, category: :comments, group_window: {10, :minute}

  deliver :feed
  deliver :email, wait: {10, :minute}, unless: :read
  deliver :telegram, if: :telegram?

  @impl true
  def recipients(%{comment: c}), do: MyApp.Stories.followers(c.story_id) -- [c.author]

  @impl true
  def data(%{comment: c}), do: %{"story_id" => c.story_id, "story" => c.story.title, "text" => c.text}

  @impl true
  def actor(%{comment: c}), do: %{"id" => "user:#{c.author.id}", "name" => c.author.name}

  @impl true
  def group(%{comment: c}), do: "story:#{c.story_id}"

  @impl true
  def feed(data, notification) do
    %{
      title: "#{Chime.actors(notification)} commented on #{data["story"]}",
      body: data["text"],
      url: "/stories/#{data["story_id"]}",
      icon: "comment"
    }
  end

  @impl true
  def email(data, _recipient, notification) do
    Swoosh.Email.new(
      subject: "#{Chime.actors(notification)} commented on #{data["story"]}",
      text_body: data["text"]
    )
  end

  def telegram(data, _recipient, notification),
    do: "#{Chime.actors(notification)} commented on #{data["story"]}"

  def telegram?(_data, recipient), do: recipient.data.telegram_chat != nil
end
```

```elixir
Chime.notify(MyApp.Notifications.NewComment, %{comment: comment}, key: "comment:#{comment.id}")
```

## `use Chime.Notifier`

* `:category` - the category of the config it is of (required): what the
  preferences turn on and off.
* `:kind` - its name in the JSON API and the components
  (`"new_comment"` for `NewComment`).
* `:required` - it goes whatever the preferences, with no link to
  unsubscribe. A category of `required: true` makes all its notifiers so.
* `:group_window` - with `group/1`, how long a notification takes the
  events of its group, from the first (`{1, :hour}`).

## Who

`recipients/1` gets the params of `Chime.notify/3` and returns the
people: your users, which the resolver's `recipient/1` turns into
`Chime.Recipient`s, recipients, or ids. Each person gets the
notification once, however many times they are in the list.

`Chime.notify/3` with `:to` gives the people instead:

```elixir
Chime.notify(MyApp.Notifications.PaymentFailed, %{invoice: invoice}, to: invoice.user)
```

## What is kept

`data/1` is what is kept of the params, as JSON: strings, numbers,
booleans, lists and maps. It is kept once on the event, whoever it goes
to, and the feed, the emails and your channels are made from it **when
they are shown or sent**, not when the notification comes. So the feed is
in the language of the person who reads it, as your words are then, and
a group's email says how many events it holds by the time it goes.

Keep what the words need, not your structs: the event outlives them. By
default, `data/1` is the params as JSON, which works for a map of plain
values.

## Groups

`group/1` returns a key, such as `"story:42"`, or nil. A person's
notification of the same key, unread and within the `:group_window`,
takes the new event instead of a new notification: its `count` goes up,
`actors` takes the new actor (`actor/1`, the latest first, each once),
it is unseen again, and it comes to the top of the feed. A read, an
archive, or the end of the window closes it: the next event is a new
notification.

`Chime.actors/1` says the actors ("Ana", "Ana and Rui", "Ana and 4
others") in your app's languages (see [Languages](languages.md)); an
app can write its own from `notification.actors` and
`notification.actor_count`.

While a group's email waits (`wait:`), the events that join the group go
with it: one email, as the group is when it goes, not one for each.

## Channels

`deliver/2` declares a channel, in the order they go:

* `deliver :feed` - the feed, at once. It takes no options.
* `deliver :email` - by the app's mailer, with `email/3`.
* `deliver :telegram` - a channel of the app's config (`Chime.Channel`),
  which calls the notifier's function of its name, `telegram/3`, when it
  has one, else uses what `feed/2` says.

Options:

* `:wait` - `{10, :minute}` (`:second`, `:minute`, `:hour`, `:day`) or
  seconds. The delivery waits, as an Oban job at its time.
* `:unless` - `:read` (the person read it in the feed meanwhile),
  `:seen` (they saw it), or the name of a function of the notifier,
  `(data, recipient) -> boolean`. A list is any of them.
* `:if` - the name of a function of the notifier, `(data, recipient) ->
  boolean`, or `{module, function}`.

Everything but the feed is decided when the delivery's time comes: the
conditions, the person's preferences then, the person themselves
(`recipients/1` of the resolver: a person who left gets nothing). Each
decision is written in the log, with its reason (see [The log](explain.md)).

## Many people

`Chime.notify/3` inserts the notifications in batches of 1000, each its
own transaction; the first is the event's, so that a call with an
idempotency key that was made already does nothing. One event to many
people is best sent from a job of your app, which Oban retries with the
same key.

## In a transaction of your app

`Chime.notify/3` inside your own `Repo.transaction/1` is part of it: the
notifications, their deliveries and their jobs are kept with your write,
or not at all. Only the live news to the open pages goes at once, before
your transaction ends.
