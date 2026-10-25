defmodule Chime.Channels.HTTP do
  @moduledoc false
  # What the channels over HTTP share: where a person is reached, what a
  # notification says as text, and the request.

  alias Chime.{Config, Message}

  @compile {:no_warn_undefined, [Req]}

  @doc false
  # The person's address of a channel: the channel's `:to` (one address
  # for everyone, such as a team's channel), or a key of the recipient's
  # data (`{:data, :phone}`; `{:data, <channel>}` by default).
  @spec address(Message.t(), keyword()) :: String.t() | nil
  def address(%Message{} = message, opts) do
    case Keyword.get(opts, :to, {:data, String.to_existing_atom(message.channel)}) do
      {:data, key} -> data(message.recipient.data, key)
      address when is_binary(address) -> address
    end
  end

  defp data(data, key) when is_map(data), do: Map.get(data, key) || Map.get(data, to_string(key))
  defp data(_data, _key), do: nil

  @doc false
  # What the notification says by the channel: the notifier's function of
  # the channel's name, else the feed's words, with the link that reads
  # it, whole.
  @spec words(Message.t()) :: %{title: String.t(), body: String.t() | nil, url: String.t() | nil}
  def words(%Message{notification: n} = message) do
    config = Config.get()

    case Message.render(message) do
      text when is_binary(text) ->
        %{title: text, body: nil, url: nil}

      %{} = words ->
        url = words[:url] && Chime.Links.address(config, Chime.link(n, words[:url]))
        %{title: words[:title] || n.kind, body: words[:body], url: url}
    end
  end

  @doc false
  # The words as one text: the title, the body, the link.
  @spec text(map()) :: String.t()
  def text(words),
    do: [words.title, words.body, words.url] |> Enum.reject(&is_nil/1) |> Enum.join("\n")

  @doc false
  @spec post(String.t(), keyword(), keyword()) :: {:ok, Req.Response.t()} | {:error, term()}
  def post(url, request, opts) do
    unless Code.ensure_loaded?(Req),
      do: raise(ArgumentError, "Chime's HTTP channels need the :req dependency")

    Req.post(url, [retry: false] ++ request ++ Keyword.get(opts, :req_options, []))
  end

  @doc false
  # A refusal that will not change with another try is skipped; the rest
  # is tried again.
  @spec result({:ok, Req.Response.t()} | {:error, term()}, String.t()) ::
          :ok | {:ok, String.t()} | {:skip, String.t()} | {:error, term()}
  def result({:ok, %{status: status}}, _name) when status in 200..299, do: :ok

  def result({:ok, %{status: status}}, name) when status in [400, 401, 403, 404, 410],
    do: {:skip, "#{name} refused it (#{status})"}

  def result({:ok, %{status: status, body: body}}, _name), do: {:error, {status, body}}
  def result({:error, error}, _name), do: {:error, error}
end
