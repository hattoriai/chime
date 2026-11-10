defmodule Chime.Channels.Push do
  @moduledoc ~S"""
  The `:push` channel: a notification on a person's devices, browsers by
  Web Push, Apple's by APNs, Android's by FCM, with the services of the
  config's `:push` (see the [Push](push.md) guide).

  What it says is the notifier's `push/3` when it has one, else what the
  feed shows:

      def push(data, _recipient, notification) do
        %{
          title: "#{Chime.actors(notification)} commented",
          body: data["text"],
          url: "/stories/#{data["story_id"]}",
          image: data["cover"],
          icon: "/icon-192.png",
          badge: "/badge-72.png"
        }
      end

  Three keys more, for an app of a phone's:

    * `:category` - what the app can do from the notification: APNs'
      `category`, the actions the iOS app registered for it (FCM and Web
      Push have it in their data, as `"category"`);
    * `:interruption_level` - `:passive`, `:active` (the default),
      `:time_sensitive` or `:critical`: APNs' `interruption-level`, and
      Web Push's urgency (`low`, `normal`, `high`);
    * `:data` - a map of the app's own, for the app on the device: the
      ids its actions need. It is at the top of APNs' payload, in FCM's
      data (as strings) and in Web Push's message, beside Chime's keys,
      which win.

  An APNs push with an `:image` or a `:category` is `mutable-content`:
  the app's notification service extension can add the image, or
  change the notification, before it is shown.

  Chime adds:

    * the link that opens the notification and reads it in the feed
      (`Chime.link/2`), from `:url`;
    * the tag of the notification's group (or its id): a newer push of
      the group replaces the one on the device, on every service;
    * the notification's id.

  It goes to every device of the person that is turned on. A device a
  service says is gone is forgotten, and the log says so. A push that
  reaches one device or more is sent; one that fails on every device is
  tried again.
  """

  @behaviour Chime.Channel

  alias Chime.{Config, Devices, Message}
  alias Chime.Push.{APNs, FCM, WebPush}

  @services %{"web" => WebPush, "apns" => APNs, "fcm" => FCM}

  @impl Chime.Channel
  def deliver(%Message{} = message, _opts) do
    config = Config.get()

    devices =
      config
      |> Devices.list(message.recipient.id, enabled: true)
      |> Enum.filter(&Map.has_key?(config.push || %{}, String.to_existing_atom(&1.kind)))

    case devices do
      [] -> {:skip, "the person has no device turned on"}
      devices -> push(config, devices, payload(config, message))
    end
  end

  defp push(config, devices, payload) do
    results =
      Enum.map(devices, fn device ->
        service = Map.fetch!(@services, device.kind)

        {device,
         service.send(
           device,
           payload,
           Map.fetch!(config.push, String.to_existing_atom(device.kind))
         )}
      end)

    sent = for {d, result} <- results, result == :ok or match?({:ok, _}, result), do: d.id
    gone = for {d, {:gone, reason}} <- results, do: {d.id, reason}
    errors = for {_d, {:error, reason}} <- results, do: reason

    Devices.used(config, sent)
    Devices.forget(config, Enum.map(gone, &elem(&1, 0)))

    forgotten =
      if gone == [],
        do: "",
        else: "; #{length(gone)} gone, forgotten: #{Enum.map_join(gone, ", ", &elem(&1, 1))}"

    cond do
      sent != [] -> {:ok, "#{length(sent)} of #{length(devices)} devices" <> forgotten}
      errors != [] -> {:error, hd(errors)}
      true -> {:skip, "every device was gone" <> forgotten}
    end
  end

  @doc false
  # What a push says: the notifier's, with the link, the tag and the id.
  def payload(config, %Message{notification: n} = message) do
    rendered = Message.render(message)

    %{
      id: n.id,
      title: rendered[:title] || n.kind,
      body: rendered[:body],
      url: rendered[:url] && Chime.Links.address(config, Chime.link(n, rendered[:url])),
      icon: rendered[:icon],
      image: rendered[:image],
      badge: rendered[:badge],
      tag: rendered[:tag] || n.group_key || n.id
    }
    |> put(:category, rendered[:category] && to_string(rendered[:category]))
    |> put(:interruption_level, level(rendered[:interruption_level]))
    |> put(:data, data(rendered[:data]))
  end

  @levels %{
    "passive" => "passive",
    "active" => "active",
    "time-sensitive" => "time-sensitive",
    "time_sensitive" => "time-sensitive",
    "critical" => "critical"
  }

  # The level as Apple writes it: "time-sensitive", from :time_sensitive too.
  defp level(nil), do: nil

  defp level(level) do
    ((is_atom(level) or is_binary(level)) && Map.get(@levels, to_string(level))) ||
      raise ArgumentError,
            "the :interruption_level of a push is :passive, :active, :time_sensitive or " <>
              ":critical, got: #{inspect(level)}"
  end

  defp data(nil), do: nil
  defp data(data) when data == %{}, do: nil
  defp data(%{} = data), do: Map.new(data, fn {k, v} -> {to_string(k), v} end)

  defp data(data),
    do: raise(ArgumentError, "the :data of a push is a map, got: #{inspect(data)}")

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
