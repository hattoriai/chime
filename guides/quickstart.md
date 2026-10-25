# Quickstart

From the dependency to the first notification in the bell.

## 1. The dependency

```elixir
# mix.exs
{:chime, "~> 0.1"}
```

Chime needs Oban, which runs every delivery but the feed's. An app
without it adds `{:oban, "~> 2.19"}` and follows
[Oban's installation](https://hexdocs.pm/oban/installation.html).

## 2. The tables

```sh
mix chime.gen.migration
mix ecto.migrate
```

The migration pins a version of `Chime.Migrations`: a later Chime that
changes the tables has a new one, and `mix chime.gen.migration` writes
the migration that upgrades.

## 3. Your people

Chime keeps people by an id of yours, a string such as `"user:42"`. A
resolver turns your users into `Chime.Recipient`s, finds them by id when
a delivery goes, and says who reads the feed of a request:

```elixir
defmodule MyApp.ChimeResolver do
  @behaviour Chime.Resolver

  import Ecto.Query

  alias MyApp.{Repo, User}

  @impl true
  def recipient(%User{} = user) do
    %Chime.Recipient{
      id: "user:#{user.id}",
      email: user.email,
      name: user.name,
      locale: user.locale,
      time_zone: user.time_zone
    }
  end

  @impl true
  def recipients(ids) do
    ids = for "user:" <> id <- ids, do: String.to_integer(id)
    from(u in User, where: u.id in ^ids) |> Repo.all() |> Enum.map(&recipient/1)
  end

  @impl true
  def resolve_recipient(%{assigns: %{current_scope: %{user: %User{} = user}}}), do: recipient(user)
  def resolve_recipient(_nobody), do: nil
end
```

`resolve_recipient/1` gets a `Plug.Conn` or a LiveView socket, after your
own pipeline and `on_mount` hooks: read the user from where your app
puts it.

## 4. Chime in your application

```elixir
# application.ex
children = [
  MyApp.Repo,
  {Phoenix.PubSub, name: MyApp.PubSub},
  {Oban, Application.fetch_env!(:my_app, Oban)},
  {Chime,
   repo: MyApp.Repo,
   pubsub: MyApp.PubSub,
   resolver: MyApp.ChimeResolver,
   mailer: MyApp.Mailer,
   email_from: {"MyApp", "hello@myapp.com"},
   secret_key_base: Application.fetch_env!(:my_app, MyAppWeb.Endpoint)[:secret_key_base],
   mail_url: "https://myapp.com/notifications/mail",
   url: "https://myapp.com",
   categories: [
     comments: [label: "Comments on your stories"],
     billing: [label: "Billing", required: true]
   ]},
  MyAppWeb.Endpoint
]
```

`Chime.Config` has every option. Chime gives its jobs to Oban's
`:default` queue; give it another with `oban: [name: Oban, queue:
:notifications]`, one your Oban runs.

## 5. A notifier

```elixir
defmodule MyApp.Notifications.NewComment do
  use Chime.Notifier, category: :comments

  deliver :feed
  deliver :email, wait: {10, :minute}, unless: :read

  @impl true
  def recipients(%{comment: comment}), do: [comment.story.author]

  @impl true
  def data(%{comment: c}), do: %{"story_id" => c.story_id, "story" => c.story.title, "author" => c.author.name}

  @impl true
  def feed(data, _notification),
    do: %{title: "#{data["author"]} commented on #{data["story"]}", url: "/stories/#{data["story_id"]}"}

  @impl true
  def email(data, _recipient, _notification),
    do: Swoosh.Email.new(subject: "#{data["author"]} commented on #{data["story"]}", text_body: "Read it in the app.")
end
```

## 6. Send it

```elixir
def create_comment(story, author, attrs) do
  with {:ok, comment} <- %Comment{} |> Comment.changeset(attrs) |> Repo.insert() do
    comment = Repo.preload(comment, [:author, story: :author])
    Chime.notify(MyApp.Notifications.NewComment, %{comment: comment}, key: "comment:#{comment.id}")
    {:ok, comment}
  end
end
```

The story's author has it in their feed at once, and an email in ten
minutes, unless they read it in the feed first.

## 7. The bell

```elixir
# router.ex
live_session :app, on_mount: [{MyAppWeb.UserAuth, :require_authenticated}, Chime.Live] do
  live "/stories", StoryLive.Index
end
```

```heex
<%!-- the app's layout, beside the user menu --%>
<div class="relative">
  <Chime.Components.bell chime={@chime} />
  <Chime.Components.feed chime={@chime} />
</div>
```

```css
/* assets/css/app.css */
@import "../../deps/chime/priv/static/chime.css";
```

## 8. The link to unsubscribe

The emails carry a link, and the headers of one-click unsubscribe, to
the config's `:mail_url`. Mount the page there, behind a pipeline
with no session and no CSRF protection, as a mail client posts it:

```elixir
import Chime.Router

pipeline :mail do
  plug :accepts, ["html"]
end

scope "/" do
  pipe_through :mail
  chime_mail "/notifications/mail", app_name: "MyApp"
end
```

## Next

* [Notifiers](notifiers.md): groups, conditions, the app's channels.
* [Preferences](preferences.md): what each person wants, and digests.
* [Any frontend](any_frontend.md): the JSON API for React.
* [Testing](testing.md).
