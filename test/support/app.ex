defmodule ChimeTest.People do
  @moduledoc """
  The people of the app of the tests, kept in an Agent: their ids are
  "user:<n>", and a person can be removed, or lose their address.
  """
  use Agent

  def start_link, do: Agent.start_link(fn -> %{} end, name: __MODULE__)

  def put(%Chime.Recipient{} = recipient),
    do: Agent.update(__MODULE__, &Map.put(&1, recipient.id, recipient))

  def delete(id), do: Agent.update(__MODULE__, &Map.delete(&1, id))
  def get(ids), do: Agent.get(__MODULE__, &(&1 |> Map.take(ids) |> Map.values()))
  def reset, do: Agent.update(__MODULE__, fn _ -> %{} end)
end

defmodule ChimeTest.User do
  @moduledoc "A user of the app of the tests."
  defstruct [:id, :name, :email, :locale, :time_zone, :quiet_hours, telegram: nil]
end

defmodule ChimeTest.Resolver do
  @moduledoc "The resolver of the tests: the people of ChimeTest.People, the reader in the session."
  @behaviour Chime.Resolver

  @impl true
  def recipient(%ChimeTest.User{} = user) do
    %Chime.Recipient{
      id: "user:#{user.id}",
      email: user.email,
      name: user.name,
      locale: user.locale,
      time_zone: user.time_zone,
      quiet_hours: user.quiet_hours,
      data: %{telegram: user.telegram}
    }
  end

  @impl true
  def recipients(ids), do: ChimeTest.People.get(ids)

  @impl true
  def resolve_recipient(%Plug.Conn{} = conn) do
    conn = Plug.Conn.fetch_session(conn)
    Plug.Conn.get_session(conn, "reader")
  end

  def resolve_recipient(%{assigns: assigns}), do: assigns[:current_reader]

  @impl true
  def resolve_workspace(%Plug.Conn{} = conn) do
    conn = Plug.Conn.fetch_session(conn)
    Plug.Conn.get_session(conn, "workspace")
  end

  def resolve_workspace(%{assigns: assigns}), do: assigns[:current_workspace]
end

defmodule ChimeTest.Telegram do
  @moduledoc """
  A channel of the app's own, for the tests: it tells the test's process
  (the pid in the options), and answers as the person's data says.
  """
  @behaviour Chime.Channel

  @impl true
  def deliver(%Chime.Message{} = message, opts) do
    case message.recipient.data[:telegram] do
      nil ->
        {:skip, "the person has no Telegram chat"}

      "fails" ->
        {:error, :timeout}

      chat ->
        text = Chime.Message.render(message)

        pid = opts[:pid] || Process.whereis(:chime_test)
        if pid, do: send(pid, {:telegram, chat, text})

        {:ok, "tg-#{chat}"}
    end
  end
end

defmodule ChimeTest.NewComment do
  @moduledoc "A notifier of the tests: a comment on a story, grouped by story."
  use Chime.Notifier, category: :comments, group_window: {10, :minute}

  deliver :feed
  deliver :email, wait: {10, :minute}, unless: :read
  deliver :telegram, if: :telegram?

  @impl true
  def recipients(%{to: to}), do: to

  @impl true
  def data(%{story: story, text: text}), do: %{"story" => story, "text" => text}

  @impl true
  def actor(%{author: author}), do: %{"id" => author, "name" => author}

  @impl true
  def group(%{story: story}), do: "story:#{story}"

  @impl true
  def feed(data, notification) do
    %{
      title: "#{Chime.actors(notification)} commented on #{data["story"]}",
      body: data["text"],
      url: "/stories/#{data["story"]}",
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

  def telegram(data, _recipient, _notification), do: "New comment on #{data["story"]}"

  def telegram?(_data, recipient), do: recipient.data[:telegram] != nil
end

defmodule ChimeTest.PaymentFailed do
  @moduledoc "A required notifier of the tests: email at once, in the feed too."
  use Chime.Notifier, category: :billing

  deliver :feed
  deliver :email

  @impl true
  def feed(data, _notification),
    do: %{title: "Your payment of #{data["amount"]} failed", url: "/billing"}

  @impl true
  def email(data, _recipient, _notification),
    do: Swoosh.Email.new(subject: "Your payment failed", text_body: "Of #{data["amount"]}.")
end

defmodule ChimeTest.Followed do
  @moduledoc "A notifier of the tests by email only, with no feed."
  use Chime.Notifier, category: :followers, kind: "followed"

  deliver :email

  @impl true
  def email(data, _recipient, _notification),
    do: Swoosh.Email.new(subject: "#{data["name"]} follows you", text_body: "Say hi.")
end

defmodule ChimeTest.DigestEmail do
  @moduledoc "The app's own digest email, for the tests."
  def email(_recipient, items, period),
    do: Swoosh.Email.new(subject: "#{length(items)} #{period}", text_body: "x")
end

defmodule ChimeTest.Liked do
  @moduledoc "A notifier of the tests whose groups share NewComment's keys."
  use Chime.Notifier, category: :comments

  deliver :feed

  @impl true
  def recipients(%{to: to}), do: to

  @impl true
  def data(%{story: story}), do: %{"story" => story}

  @impl true
  def actor(%{author: author}), do: %{"id" => author, "name" => author}

  @impl true
  def group(%{story: story}), do: "story:#{story}"

  @impl true
  def feed(data, notification),
    do: %{title: "#{Chime.actors(notification)} liked #{data["story"]}"}
end

defmodule ChimeTest.Raises do
  @moduledoc "A notifier of the tests whose email raises."
  use Chime.Notifier, category: :comments

  deliver :email

  @impl true
  def group(_params), do: "always"

  @impl true
  def email(_data, _recipient, _notification), do: raise("boom")
end

defmodule ChimeTest.InTeam do
  @moduledoc "A notifier of the tests whose workspace is the params' team."
  use Chime.Notifier, category: :comments

  deliver :feed

  @impl true
  def workspace(%{team: team}), do: "team:#{team}"

  @impl true
  def feed(_data, _notification), do: %{title: "In a team"}
end

defmodule ChimeTest.Notifier do
  @moduledoc """
  The app's base of its notifiers, as an ApplicationNotifier: the feed for
  all, a guard every notifier has, and its own defaults.
  """
  defmacro __using__(opts) do
    quote do
      use Chime.Notifier, unquote(opts)

      deliver :feed, if: :can_read?

      # Who may read the channel: the people of the test's list.
      def can_read?(data, recipient), do: recipient.id in Map.get(data, "members", [recipient.id])

      @impl Chime.Notifier
      def notify?(params, recipient), do: recipient.id not in Map.get(params, :blocked, [])

      defoverridable notify?: 2
    end
  end
end

defmodule ChimeTest.ChannelMessage do
  @moduledoc "A notifier of the tests on the app's base."
  use ChimeTest.Notifier, category: :comments

  deliver :email, wait: {1, :minute}

  @impl true
  def recipients(%{to: to}), do: to

  @impl true
  def data(%{members: members} = params), do: %{"text" => params.text, "members" => members}
  def data(params), do: %{"text" => params.text}

  @impl true
  def actor(%{author: author}), do: %{"id" => author, "name" => author}

  @impl true
  def feed(data, _notification), do: %{title: data["text"]}

  @impl true
  def email(data, _recipient, _notification), do: Swoosh.Email.new(subject: data["text"])
end

defmodule ChimeTest.SelfToo do
  @moduledoc "A notifier of the tests that tells its actor too."
  use Chime.Notifier, category: :comments, notify_actor: true

  deliver :feed

  @impl true
  def actor(%{author: author}), do: %{"id" => author, "name" => author}

  @impl true
  def feed(_data, _notification), do: %{title: "You did it"}
end

defmodule ChimeTest.DirectMessage do
  @moduledoc """
  A notifier of the tests as Superwave's DMs: quick messages from one
  sender go as one email (debounce), at most one email of a conversation
  in 15 minutes (throttle).
  """
  use Chime.Notifier, category: :comments, group_window: {1, :day}

  deliver :feed

  deliver :email,
    wait: {1, :minute},
    debounce: true,
    max_wait: {5, :minute},
    throttle: {15, :minute}

  deliver :telegram, quiet: false

  @impl true
  def data(%{text: text}), do: %{"text" => text}

  @impl true
  def actor(%{from: from}), do: %{"id" => from, "name" => from}

  @impl true
  def group(%{from: from}), do: "dm:#{from}"

  @impl true
  def feed(data, notification), do: %{title: "#{Chime.actors(notification)}: #{data["text"]}"}

  @impl true
  def email(data, _recipient, notification),
    do:
      Swoosh.Email.new(
        subject: "#{notification.count} from #{Chime.actors(notification)}",
        text_body: data["text"]
      )

  def telegram(data, _recipient, _notification), do: data["text"]
end

defmodule ChimeTest.Announcement do
  @moduledoc "A notifier of the tests to everyone confirmed: an audience of the app's table."
  use Chime.Notifier, category: :comments

  import Ecto.Query

  deliver :feed

  @impl true
  def audience(%{"only" => "unconfirmed"}),
    do: from(u in ChimeTest.UserRow, where: not u.confirmed)

  def audience(_data),
    do: from(u in ChimeTest.UserRow, where: u.confirmed, order_by: [desc: u.name])

  @impl true
  def recipient_id(id), do: "user:#{id}"

  @impl true
  def data(params), do: Chime.Notifier.json!(__MODULE__, params)

  @impl true
  def actor(params), do: params["by"] && %{"id" => params["by"], "name" => "Admin"}

  @impl true
  def feed(data, _notification), do: %{title: data["title"]}
end

defmodule ChimeTest.Invited do
  @moduledoc "A notifier of the tests with actions: an invitation to accept or decline."
  use Chime.Notifier, category: :comments

  deliver :feed
  deliver :email

  @impl true
  def data(%{team: team}), do: %{"team" => team}

  @impl true
  def feed(data, %{action: nil}) do
    %{
      title: "You are invited to #{data["team"]}",
      url: "/teams/#{data["team"]}",
      actions: [%{key: "accept", label: "Accept"}, %{key: "decline", label: "Decline"}]
    }
  end

  def feed(data, %{action: action}),
    do: %{title: "You #{action}ed #{data["team"]}", url: "/teams/#{data["team"]}"}

  @impl true
  def act("accept", %{"team" => "full"}, _notification), do: {:error, :team_full}
  def act("accept", data, _notification), do: {:ok, "/teams/#{data["team"]}"}
  def act("decline", _data, _notification), do: :ok

  @impl true
  def email(data, _recipient, notification) do
    Swoosh.Email.new(
      subject: "Join #{data["team"]}",
      html_body: ~s(<a href="#{Chime.link(notification, "/teams/#{data["team"]}")}">Join</a>)
    )
  end
end
