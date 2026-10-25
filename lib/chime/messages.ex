defmodule Chime.Messages do
  @moduledoc ~S"""
  Chime's words, in the app's languages, by the app's own Gettext. Chime
  ships English, and a template of its words; the app translates them as
  it translates its own.

      {Chime, ..., gettext: MyAppWeb.Gettext}

  With `:gettext`, every word of Chime's (the bell and the feed, the
  preferences, "Ana and 4 others", the digest's email, the page to
  unsubscribe) is looked up in the `"chime"` domain of the app's backend,
  in its locale of the moment. Copy Chime's template into the app's, and
  make the languages' files from it:

      $ cp deps/chime/priv/gettext/chime.pot priv/gettext/
      $ mix gettext.merge priv/gettext

  `mix gettext.merge` makes `priv/gettext/<locale>/LC_MESSAGES/chime.po`
  for each of the app's languages, to translate as the app's own. After an
  upgrade of Chime, copy the template again and merge: the new words come,
  the translations stay. A word not translated is English.

  The labels and descriptions of the config's `:categories` are looked up
  in the same domain: add them to the app's `chime.po` files as more
  `msgid`s.

  ## The locale

  The feed, the bell and the JSON API speak the locale of the request or
  the LiveView, as the app's own plugs and hooks set it. What a job sends
  (the email and the channels of a delivery, the digests) speaks the
  person's `:locale` (`Chime.Recipient`): Chime runs it in
  `Gettext.with_locale/3`, so the notifier's own `gettext` calls in its
  `email/3` speak it too.
  """

  # Gettext is an optional dependency, with the :gettext option.
  @compile {:no_warn_undefined, [Gettext]}

  @domain "chime"

  @doc "A word of Chime's, in the locale of the moment."
  @spec t(String.t(), map() | keyword()) :: String.t()
  def t(msgid, bindings \\ %{}) do
    bindings = Map.new(bindings)

    case backend() do
      nil -> interpolate(msgid, bindings)
      backend -> Gettext.dgettext(backend, @domain, msgid, bindings)
    end
  end

  @doc "A word of Chime's with a plural, by `count`."
  @spec tn(String.t(), String.t(), integer(), map() | keyword()) :: String.t()
  def tn(msgid, plural, count, bindings \\ %{}) do
    bindings = Map.new(bindings)

    case backend() do
      nil ->
        interpolate(if(count == 1, do: msgid, else: plural), Map.put(bindings, :count, count))

      backend ->
        Gettext.dngettext(backend, @domain, msgid, plural, count, bindings)
    end
  end

  @doc false
  # Runs `fun` in a person's locale, when the app has a Gettext and the
  # person a locale.
  @spec with_locale(String.t() | nil, (-> result)) :: result when result: term()
  def with_locale(nil, fun), do: fun.()

  def with_locale(locale, fun) do
    case backend() do
      nil -> fun.()
      backend -> Gettext.with_locale(backend, locale, fun)
    end
  end

  defp backend do
    case :persistent_term.get({Chime, :config}, nil) do
      %{gettext: backend} -> backend
      _ -> nil
    end
  end

  defp interpolate(text, bindings) do
    Enum.reduce(bindings, text, fn {key, value}, text ->
      String.replace(text, "%{#{key}}", to_string(value))
    end)
  end
end
