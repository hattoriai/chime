# Languages

Chime ships English and a template of its words. Your app translates
them as it translates its own, with its own Gettext: Chime ships no
languages to keep up to date.

## Setup

Give Chime your backend:

```elixir
{Chime, ..., gettext: MyAppWeb.Gettext}
```

Copy Chime's template beside yours, and make each language's file from
it:

```sh
cp deps/chime/priv/gettext/chime.pot priv/gettext/
mix gettext.merge priv/gettext
```

`priv/gettext/<locale>/LC_MESSAGES/chime.po` is then there for each of
your languages, to translate with the tools you use for the rest. A word
not translated stays English.

After an upgrade of Chime, copy the template again and merge: the new
words come, your translations stay.

## What is translated

* The bell, the feed and the preferences (`Chime.Components`).
* "Ana and Rui", "Ana and 4 others" (`Chime.actors/1`).
* The digest's email, and the page to unsubscribe.
* The labels and descriptions of your `:categories`: add them to your
  `chime.po` files as `msgid`s of their own, and they are looked up there.

The log (`Chime.explain/1`) is for you, and stays English.

## Whose language

* **The feed, the bell, the preferences and the JSON API** speak the
  locale of the request or the LiveView, as your app's plugs and
  `on_mount` hooks set it.
* **What a job sends** (each email and channel of a delivery, the
  digests) speaks the person's own: the `:locale` of their
  `Chime.Recipient`. Chime runs it in `Gettext.with_locale/3`, so your
  notifier's own `gettext` calls in `email/3` speak it too:

```elixir
use Gettext, backend: MyAppWeb.Gettext

def email(data, _recipient, notification) do
  Swoosh.Email.new(subject: gettext("%{who} commented on %{story}", who: Chime.actors(notification), story: data["story"]))
end
```

* **The page to unsubscribe** speaks the person's, from the link.
