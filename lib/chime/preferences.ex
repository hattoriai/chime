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
  # The settings people kept for a category, of these people, by person,
  # in a workspace (nil for none): %{recipient => %{key => {setting,
  # updated_at}}}, the key telling which setting it is (setting/4).
  @spec stored(Config.t(), [String.t()], String.t(), String.t() | nil) :: %{String.t() => map()}
  def stored(%Config{} = config, ids, category, workspace \\ nil) do
    from(p in Preference,
      where:
        p.recipient in ^ids and p.category in [^category, @all] and
          p.workspace in ^Enum.uniq(["", workspace || ""]),
      select: {p.recipient, p.workspace, p.category, p.channel, p.setting, p.updated_at}
    )
    |> config.repo.all(prefix: config.prefix)
    |> Enum.reduce(%{}, fn {recipient, ws, cat, channel, setting, at}, acc ->
      key = key(ws, cat, channel)
      Map.update(acc, recipient, %{key => {setting, at}}, &Map.put(&1, key, {setting, at}))
    end)
  end

  defp key("", @all, channel), do: {:all, channel}
  defp key("", _category, channel), do: channel
  defp key(_workspace, @all, channel), do: {:workspace_all, channel}
  defp key(_workspace, _category, channel), do: {:workspace, channel}

  @doc false
  # A person's setting of a channel for a category, from what they kept
  # (stored/4): {setting, kept_at}, kept_at nil for a default. The
  # workspace's own setting of the category comes first, then the
  # workspace's for all, then the category's, then the one for all.
  @spec setting(Config.category(), boolean(), map(), String.t()) ::
          {String.t(), DateTime.t() | nil}
  def setting(category, required?, kept, channel)

  def setting(_category, true, _kept, _channel), do: {"on", nil}

  def setting(category, false, kept, channel) do
    Enum.find_value(
      [{:workspace, channel}, {:workspace_all, channel}, channel, {:all, channel}],
      {Map.get(category.defaults, channel, "on"), nil},
      &Map.get(kept, &1)
    )
  end

  @doc """
  A person's settings, for each category of the config: in a workspace,
  its own where the person set them, else their settings for all.
  """
  @spec for_recipient(Config.t(), String.t(), String.t() | nil) :: [t()]
  def for_recipient(config, recipient, workspace \\ nil)
  def for_recipient(%Config{categories: nil}, _recipient, _workspace), do: []

  def for_recipient(%Config{} = config, recipient, workspace) when is_binary(recipient) do
    channels = Config.channel_names(config)

    kept =
      from(p in Preference,
        where: p.recipient == ^recipient and p.workspace in ^Enum.uniq(["", workspace || ""]),
        select: {p.workspace, p.category, p.channel, p.setting, p.updated_at}
      )
      |> config.repo.all(prefix: config.prefix)

    Enum.map(config.categories, fn category ->
      kept =
        for {ws, cat, channel, setting, at} <- kept,
            cat in [category.key, @all],
            into: %{},
            do: {key(ws, cat, channel), {setting, at}}

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
  Changes a person's setting of a channel for a category, for every
  workspace, or for one (`workspace`). Errors: `:required` (the category
  is required), `:unknown_category`, `:unknown_channel`,
  `:invalid_setting` (a setting that is not `"on"` or `"off"`, or
  `"daily"` or `"weekly"` for email).
  """
  @spec put(Config.t(), String.t(), String.t(), String.t(), String.t(), String.t() | nil) ::
          :ok | {:error, :required | :unknown_category | :unknown_channel | :invalid_setting}
  def put(%Config{} = config, recipient, category, channel, setting, workspace \\ nil)
      when is_binary(recipient) do
    with {:ok, spec} <- category(config, category),
         :ok <- check_channel(config, channel),
         :ok <- check_setting(channel, setting) do
      if spec.required,
        do: {:error, :required},
        else: write(config, recipient, workspace || "", category, channel, setting)
    end
  end

  @doc false
  # The link to unsubscribe of an email: its category off by email; of a
  # digest ("*"), email off for every category. In every workspace: the
  # workspaces' own settings of it go.
  @spec unsubscribe(Config.t(), String.t(), String.t()) :: :ok
  def unsubscribe(%Config{} = config, recipient, @all) do
    config.repo.transaction(fn ->
      from(p in Preference, where: p.recipient == ^recipient and p.channel == "email")
      |> config.repo.delete_all(prefix: config.prefix)

      write(config, recipient, "", @all, "email", "off")
    end)

    :ok
  end

  def unsubscribe(%Config{} = config, recipient, category) do
    required? =
      try do
        config.categories != nil and Config.category(config, category).required
      rescue
        # A category the config no longer has: the setting is kept all the same.
        ArgumentError -> false
      end

    unless required? do
      config.repo.transaction(fn ->
        from(p in Preference,
          where:
            p.recipient == ^recipient and p.channel == "email" and p.category == ^category and
              p.workspace != ""
        )
        |> config.repo.delete_all(prefix: config.prefix)

        write(config, recipient, "", category, "email", "off")
      end)
    end

    :ok
  end

  defp write(config, recipient, workspace, category, channel, setting) do
    config.repo.insert_all(
      Preference,
      [
        %{
          recipient: recipient,
          workspace: workspace,
          category: category,
          channel: channel,
          setting: setting,
          updated_at: DateTime.utc_now()
        }
      ],
      on_conflict: {:replace, [:setting, :updated_at]},
      conflict_target: [:recipient, :workspace, :category, :channel],
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
