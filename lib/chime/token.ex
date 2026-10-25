defmodule Chime.Token do
  @moduledoc ~S"""
  Signed tokens of a person, for the JSON API (`Chime.API`) where the
  app's own session or token does not reach: an `EventSource` cannot send
  an `authorization` header, and a page on another origin has no cookie
  of the app's.

      # in a controller of the app, for its signed-in user
      json(conn, %{token: Chime.Token.sign("user:#{user.id}")})

  The frontend gives it to the API as `Bearer <token>`, or as `?token=`
  to `/stream`. `POST /token` of the API makes one for the person of the
  request, too. A token is a `Phoenix.Token`, signed with the config's
  `:secret_key_base` and a salt of Chime's own, valid for a day (`:max_age`
  of `verify/2`). Make one on the server, for the person the page is for,
  never from an id the browser sends.

  The links to unsubscribe of the emails are tokens too, of another salt,
  that do not expire.
  """

  alias Chime.Config

  @reader "chime reader"
  @unsubscribe "chime unsubscribe"
  @open "chime open"
  @max_age 86_400

  @doc "A token of a person, by their id."
  @spec sign(String.t()) :: String.t()
  def sign(recipient) when is_binary(recipient) do
    Phoenix.Token.sign(secret!(Config.get()), @reader, recipient)
  end

  @doc """
  The person of a token of `sign/1`: `{:ok, id}`, `{:error, :expired}`
  past `:max_age` seconds (86400), or `{:error, :invalid}`.
  """
  @spec verify(String.t(), keyword()) :: {:ok, String.t()} | {:error, :expired | :invalid}
  def verify(token, opts \\ []) when is_binary(token) do
    case Config.get().secret_key_base do
      nil ->
        {:error, :invalid}

      secret ->
        case Phoenix.Token.verify(secret, @reader, token,
               max_age: Keyword.get(opts, :max_age, @max_age)
             ) do
          {:ok, id} when is_binary(id) -> {:ok, id}
          {:error, :expired} -> {:error, :expired}
          _ -> {:error, :invalid}
        end
    end
  end

  @doc false
  # The address to unsubscribe a person from a category's emails ("*" for
  # all), or nil without the config's :mail_url and secret.
  @spec unsubscribe_url(Config.t(), String.t(), String.t()) :: String.t() | nil
  def unsubscribe_url(%Config{mail_url: nil}, _recipient, _category), do: nil
  def unsubscribe_url(%Config{secret_key_base: nil}, _recipient, _category), do: nil

  def unsubscribe_url(%Config{} = config, recipient, category) do
    token = Phoenix.Token.sign(config.secret_key_base, @unsubscribe, [recipient, category])
    config.mail_url <> "/unsubscribe/" <> token
  end

  @doc false
  # A link that opens a notification: read, then the address. nil without
  # the config's :mail_url and secret.
  @spec open_url(Config.t(), Ecto.UUID.t(), String.t(), String.t()) :: String.t() | nil
  def open_url(%Config{mail_url: nil}, _id, _recipient, _url), do: nil
  def open_url(%Config{secret_key_base: nil}, _id, _recipient, _url), do: nil

  def open_url(%Config{} = config, id, recipient, url) do
    token = Phoenix.Token.sign(config.secret_key_base, @open, [id, recipient, url])
    config.mail_url <> "/open/" <> token
  end

  @doc false
  @spec verify_open(Config.t(), String.t()) ::
          {:ok, Ecto.UUID.t(), String.t(), String.t()} | :error
  def verify_open(%Config{secret_key_base: nil}, _token), do: :error

  def verify_open(%Config{} = config, token) do
    case Phoenix.Token.verify(config.secret_key_base, @open, token, max_age: :infinity) do
      {:ok, [id, recipient, url]}
      when is_binary(id) and is_binary(recipient) and is_binary(url) ->
        {:ok, id, recipient, url}

      _ ->
        :error
    end
  end

  @doc false
  # The person and category of a link to unsubscribe.
  @spec verify_unsubscribe(Config.t(), String.t()) :: {:ok, String.t(), String.t()} | :error
  def verify_unsubscribe(%Config{secret_key_base: nil}, _token), do: :error

  def verify_unsubscribe(%Config{} = config, token) do
    case Phoenix.Token.verify(config.secret_key_base, @unsubscribe, token, max_age: :infinity) do
      {:ok, [recipient, category]} when is_binary(recipient) and is_binary(category) ->
        {:ok, recipient, category}

      _ ->
        :error
    end
  end

  defp secret!(%Config{secret_key_base: nil}),
    do: raise(ArgumentError, "Chime's tokens need the :secret_key_base option")

  defp secret!(%Config{secret_key_base: secret}), do: secret
end
