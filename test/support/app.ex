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
  defstruct [:id, :name, :email, :locale, :time_zone, telegram: nil]
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
