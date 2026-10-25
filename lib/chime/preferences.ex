defmodule Chime.Preferences do
  @moduledoc """
  What each person wants to hear about: a setting for each category of
  `Chime.Config` and each channel.

    * `"on"` - it goes;
    * `"off"` - it does not, and the log says the person turned it off;
    * `"daily"` and `"weekly"` - for email: it waits for the person's
      digest (`Chime.Digest`).

  A setting the person has not changed is the category's default
  (`:defaults` in `Chime.Config`), else `"on"`. A required category
  (`required: true`) is always `"on"`: its settings cannot be changed.

  `Chime.preferences/1` reads a person's, `Chime.put_preference/4` changes
  one, and the JSON API (`Chime.API`) and the LiveView component
  (`Chime.Components.preferences/1`) are both over them.
  """

  import Ecto.Query

  alias Chime.{Config, Preference}

  # The category of a setting for all the categories: what the link to
  # unsubscribe of a digest writes.
  @all "*"

  @typedoc "A category and the person's settings of its channels."
  @type t :: %{
          category: Config.category(),
          settings: %{String.t() => String.t()}
        }

  @doc false
  # The settings people kept for a category, of these people, by person:
  # %{recipient => %{channel => {setting, updated_at}}}.
  @spec stored(Config.t(), [String.t()], String.t()) :: %{String.t() => map()}
  def stored(%Config{} = config, ids, category) do
    from(p in Preference,
      where: p.recipient in ^ids and p.category in [^category, @all],
      select: {p.recipient, p.category, p.channel, p.setting, p.updated_at}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Enum.reduce(%{}, fn {recipient, cat, channel, setting, at}, acc ->
      # A category's own setting comes before the setting for all.
      key = if cat == @all, do: {:all, channel}, else: channel
      Map.update(acc, recipient, %{key => {setting, at}}, &Map.put(&1, key, {setting, at}))
    end)
  end

  @doc false
  # A person's setting of a channel for a category, from what they kept
  # (stored/3): {setting, kept_at}, kept_at nil for a default.
  @spec setting(Config.category(), boolean(), map(), String.t()) ::
          {String.t(), DateTime.t() | nil}
  def setting(category, required?, kept, channel)

  def setting(_category, true, _kept, _channel), do: {"on", nil}

  def setting(category, false, kept, channel) do
    case kept do
      %{^channel => kept} -> kept
      %{{:all, ^channel} => kept} -> kept
      _ -> {Map.get(category.defaults, channel, "on"), nil}
    end
  end

  @doc "A person's settings, for each category of the config."
  @spec for_recipient(Config.t(), String.t()) :: [t()]
  def for_recipient(%Config{categories: nil}, _recipient), do: []

  def for_recipient(%Config{} = config, recipient) when is_binary(recipient) do
    channels = Config.channel_names(config)

    kept =
      from(p in Preference,
        where: p.recipient == ^recipient,
        select: {p.category, p.channel, p.setting, p.updated_at}
      )
      |> config.repo.all(prefix: config.prefix)
      |> Enum.group_by(&elem(&1, 0), fn {_cat, channel, setting, at} ->
        {channel, {setting, at}}
      end)

    all = for {channel, kept} <- Map.get(kept, @all, []), into: %{}, do: {{:all, channel}, kept}

    Enum.map(config.categories, fn category ->
      own = Map.new(Map.get(kept, category.key, []))
      kept = Map.merge(all, own)

      %{
        category: category,
        settings:
          Map.new(channels, fn channel ->
            {setting, _at} = setting(category, category.required, kept, channel)
            {channel, setting}
          end)
      }
    end)
  end

  @doc """
  Changes a person's setting of a channel for a category. Errors:
  `:required` (the category is required), `:unknown_category`,
  `:unknown_channel`, `:invalid_setting` (a setting that is not `"on"` or
  `"off"`, or `"daily"` or `"weekly"` for email).
  """
  @spec put(Config.t(), String.t(), String.t(), String.t(), String.t()) ::
          :ok | {:error, :required | :unknown_category | :unknown_channel | :invalid_setting}
  def put(%Config{} = config, recipient, category, channel, setting)
      when is_binary(recipient) do
    with {:ok, spec} <- category(config, category),
         :ok <- check_channel(config, channel),
         :ok <- check_setting(channel, setting) do
      if spec.required,
        do: {:error, :required},
        else: write(config, recipient, category, channel, setting)
    end
  end

  @doc false
  # The link to unsubscribe of an email: its category off by email; of a
  # digest ("*"), email off for every category.
  @spec unsubscribe(Config.t(), String.t(), String.t()) :: :ok
  def unsubscribe(%Config{} = config, recipient, @all) do
    config.repo.transaction(fn ->
      from(p in Preference, where: p.recipient == ^recipient and p.channel == "email")
      |> config.repo.delete_all(prefix: config.prefix)

      write(config, recipient, @all, "email", "off")
    end)

    :ok
  end

  def unsubscribe(%Config{} = config, recipient, category) do
    case config.categories && Config.category(config, category) do
      %{required: true} -> :ok
      _ -> write(config, recipient, category, "email", "off")
    end
  rescue
    # A category the config no longer has: the setting is kept all the same.
    ArgumentError -> write(config, recipient, category, "email", "off")
  end

  defp write(config, recipient, category, channel, setting) do
    config.repo.insert_all(
      Preference,
      [
        %{
          recipient: recipient,
          category: category,
          channel: channel,
          setting: setting,
          updated_at: DateTime.utc_now()
        }
      ],
      on_conflict: {:replace, [:setting, :updated_at]},
      conflict_target: [:recipient, :category, :channel],
      prefix: config.prefix
    )

    :ok
  end

  defp category(%Config{categories: nil}, _key), do: {:error, :unknown_category}

  defp category(%Config{categories: categories}, key) do
    case Enum.find(categories, &(&1.key == key)) do
      nil -> {:error, :unknown_category}
      spec -> {:ok, spec}
    end
  end

  defp check_channel(config, channel) do
    if channel in Config.channel_names(config), do: :ok, else: {:error, :unknown_channel}
  end

  defp check_setting("email", setting) when setting in ~w(on off daily weekly), do: :ok
  defp check_setting(_channel, setting) when setting in ~w(on off), do: :ok
  defp check_setting(_channel, _setting), do: {:error, :invalid_setting}
end
