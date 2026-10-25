# Testing

`Chime.Test` asserts what your app notified, reads a person's feed, and
runs the deliveries in your tests, in the test's process, with no Oban
to drain and no clock to wait for.

```elixir
import Chime.Test
import Swoosh.TestAssertions

test "a comment notifies the story's author", %{story: story} do
  {:ok, comment} = Stories.comment(story, ana(), %{text: "Lovely."})

  notification = assert_notified(MyApp.Notifications.NewComment, to: story.author, data: %{"story" => "Tokyo"})
  assert notification.count == 1

  assert [%{title: "Ana commented on Tokyo", read: false}] = feed(story.author)
  refute_notified(MyApp.Notifications.NewComment, to: ana())

  # The email waits ten minutes, unless the author reads it first.
  assert [] = deliver(channel: :email)
  assert [%Chime.Delivery{status: "sent"}] = deliver(at: DateTime.add(DateTime.utc_now(), 11, :minute))
  assert_email_sent(subject: "Ana commented on Tokyo")
end

test "the email is not sent when the comment was read" do
  {:ok, _} = Stories.comment(story, ana(), %{text: "Lovely."})
  [%{id: id}] = feed(story.author)
  Chime.mark_read("user:#{story.author.id}", [id])

  assert [%Chime.Delivery{status: "skipped", reason: "read in the feed at " <> _}] =
           deliver(at: DateTime.add(DateTime.utc_now(), 11, :minute))
end
```

* `assert_notified/2`, `refute_notified/2` - a notifier and `:to` (your
  user, a recipient or an id), and `:data` the event's data must contain.
* `feed/2` - the person's feed as the JSON API gives it, with atom keys.
* `deliver/1` - runs the deliveries whose time came, as their jobs would:
  `:at` (now), `:to`, `:channel`, `:last_attempt`. It returns them as they
  are after.
* `deliveries/2` - a person's deliveries.
* `run_scheduled/1` - the scheduled notifications due at a time.
* `run_audiences/0` - every page of the audiences being sent.
* `run_digests/1` - the digests due at a time.
* `explain/1` - the log of a notification, as text.
* `events/1` - the events of a notifier.

## The setup

Chime is in your supervision tree in the tests too, with your test repo.
Start it with `scheduler: false`, so that no digest or cleanup job is
given to Oban at boot, and run Oban with `testing: :manual`, so that the
deliveries wait for `deliver/1`: with `:inline`, Oban would send them at
once, before their time.

```elixir
# application.ex
{Chime, repo: MyApp.Repo, ..., scheduler: Application.get_env(:my_app, :chime_scheduler, true)}

# config/test.exs
config :my_app, :chime_scheduler, false
config :my_app, Oban, testing: :manual
config :my_app, MyApp.Mailer, adapter: Swoosh.Adapters.Test
```

The emails of Swoosh's test adapter come to the process that sends them:
`deliver/1` sends in the test's, so `Swoosh.TestAssertions` sees them.

## In LiveView

The bell and the feed are LiveView markup, tested as any other:

```elixir
{:ok, view, _html} = live(conn, ~p"/stories")
assert has_element?(view, ".chime-dot")

view |> element(".chime-bell") |> render_click()
assert has_element?(view, ".chime-item", "Ana commented on Tokyo")
```

A notification sent while the page is open reaches it: `render(view)`
after `Chime.notify/3` shows it.
