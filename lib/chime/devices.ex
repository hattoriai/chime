defmodule Chime.Devices do
  @moduledoc false
  # A person's devices: registered, listed, turned off and on, removed,
  # and forgotten when a service says they are gone.

  import Ecto.Query

  alias Chime.{Config, Device}

  @doc false
  @spec register(Config.t(), String.t(), map()) :: {:ok, Device.t()} | {:error, atom()}
  def register(%Config{} = config, recipient, attrs) do
    attrs = Map.new(attrs, fn {k, v} -> {to_string(k), v} end)
    kind = attrs["kind"]
    token = attrs["token"]
    keys = attrs["keys"]

    with :ok <- check(kind, token, keys) do
      now = DateTime.utc_now()

      row = %{
        id: Ecto.UUID.generate(),
        recipient: recipient,
        kind: kind,
        token: token,
        keys: if(kind == "web", do: Map.take(keys, ["p256dh", "auth"])),
        name: attrs["name"] && String.slice(to_string(attrs["name"]), 0, 255),
        enabled: true,
        inserted_at: now,
        updated_at: now
      }

      # A token is one device, of whoever registers it last (a phone
      # signed in as another person).
      config.repo.insert_all(Device, [row],
        on_conflict: {:replace, [:recipient, :keys, :name, :enabled, :updated_at]},
        conflict_target: [:kind, :token],
        prefix: config.prefix
      )

      {:ok, config.repo.get_by!(Device, [kind: kind, token: token], prefix: config.prefix)}
    end
  end

  defp check(kind, token, keys) do
    cond do
      kind not in Device.kinds() -> {:error, :unknown_kind}
      not is_binary(token) or token == "" or byte_size(token) > 4096 -> {:error, :invalid_token}
      kind == "web" and not web?(token, keys) -> {:error, :invalid_subscription}
      true -> :ok
    end
  end

  # A Web Push subscription: an https endpoint, and its keys.
  defp web?("https://" <> _, %{"p256dh" => p256dh, "auth" => auth})
       when is_binary(p256dh) and is_binary(auth) do
    match?({:ok, <<4, _::binary-64>>}, Base.url_decode64(p256dh, padding: false)) and
      match?({:ok, <<_::binary-16>>}, Base.url_decode64(auth, padding: false))
  end

  defp web?(_token, _keys), do: false

  @doc false
  @spec list(Config.t(), String.t(), keyword()) :: [Device.t()]
  def list(%Config{} = config, recipient, opts \\ []) do
    from(d in Device, where: d.recipient == ^recipient, order_by: [desc: d.updated_at])
    |> then(&if(opts[:enabled], do: where(&1, [d], d.enabled), else: &1))
    |> config.repo.all(prefix: config.prefix)
  end

  @doc false
  @spec update(Config.t(), String.t(), Ecto.UUID.t(), map()) ::
          {:ok, Device.t()} | {:error, :not_found}
  def update(%Config{} = config, recipient, id, changes) do
    changes = for {k, v} <- changes, k in [:enabled, :name], do: {k, v}

    with {:ok, id} <- Ecto.UUID.cast(id),
         {1, _} <-
           from(d in Device, where: d.id == ^id and d.recipient == ^recipient)
           |> config.repo.update_all([set: [updated_at: DateTime.utc_now()] ++ changes],
             prefix: config.prefix
           ) do
      {:ok, config.repo.get!(Device, id, prefix: config.prefix)}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc false
  @spec remove(Config.t(), String.t(), Ecto.UUID.t()) :: :ok | {:error, :not_found}
  def remove(%Config{} = config, recipient, id) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         {1, _} <-
           config.repo.delete_all(
             from(d in Device, where: d.id == ^id and d.recipient == ^recipient),
             prefix: config.prefix
           ) do
      :ok
    else
      _ -> {:error, :not_found}
    end
  end

  @doc false
  # The devices a service said are gone.
  @spec forget(Config.t(), [Ecto.UUID.t()]) :: :ok
  def forget(_config, []), do: :ok

  def forget(%Config{} = config, ids) do
    config.repo.delete_all(from(d in Device, where: d.id in ^ids), prefix: config.prefix)
    :ok
  end

  @doc false
  @spec used(Config.t(), [Ecto.UUID.t()]) :: :ok
  def used(_config, []), do: :ok

  def used(%Config{} = config, ids) do
    from(d in Device, where: d.id in ^ids)
    |> config.repo.update_all([set: [last_used_at: DateTime.utc_now()]], prefix: config.prefix)

    :ok
  end
end
