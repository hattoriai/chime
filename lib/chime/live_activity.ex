defmodule Chime.LiveActivity do
  @moduledoc ~S"""
  A Live Activity on an iPhone, changed or ended from the server: APNs'
  `liveactivity` push, with the keys of the config's `:apns` (see the
  [Push](push.md) guide).

  The app starts the activity, asks it for its push token, and sends the
  token to the server. The server keeps it with what the activity shows
  (a delivery, a match, a walk) and, when that changes, pushes the
  activity's new content:

      Chime.LiveActivity.update(token, %{"status" => "On the way", "eta" => 12})

  When it is over, also when the app cannot say so (the phone is off,
  iOS stopped the app), the server ends it:

      Chime.LiveActivity.finish(token, %{"status" => "Delivered"},
        dismissal_date: DateTime.utc_now()
      )

  The content state is the activity's own: its keys are those of the
  app's `ActivityAttributes.ContentState`, as the app decodes them.

  A Live Activity is not a notification: no person, no feed, no
  preferences, no device of `Chime.register_device/2`. Each call is one
  push, now, to one activity.

  Each function gives `{:ok, apns_id}`, `{:gone, reason}` when the
  activity is over on the device or its token is not the app's (forget
  the token), or `{:error, reason}`: APNs' answer, or `:no_apns` when the
  config's `:push` has no `:apns`.
  """

  alias Chime.Config
  alias Chime.Push.APNs

  @type result :: {:ok, String.t()} | {:gone, String.t()} | {:error, term()}

  @doc """
  Changes a Live Activity's content.

  Options:

    * `:alert` - `%{title: ..., body: ...}`: the activity also lights the
      screen and shows these words (APNs' `alert`).
    * `:stale_date` - a `DateTime` after which the device shows the
      content as old (APNs' `stale-date`).
    * `:relevance_score` - a number: which of the app's activities is on
      top, the highest.
    * `:priority` - `:high` (the default; APNs' 10) or `:low` (5): Apple
      limits the high ones an app sends in an hour.
    * `:timestamp` - a `DateTime`, the time of the content (now): the
      device ignores a push older than the content it has.
  """
  @spec update(String.t(), map(), keyword()) :: result()
  def update(token, content_state, opts \\ []) when is_binary(token) and is_map(content_state) do
    "update"
    |> aps(content_state, opts)
    |> put(:alert, alert(opts[:alert]))
    |> put(:"stale-date", unix(opts[:stale_date]))
    |> put(:"relevance-score", opts[:relevance_score])
    |> push(token, opts)
  end

  @doc """
  Ends a Live Activity, with its last content.

  Options: those of `update/3`, and `:dismissal_date`, a `DateTime` when
  the ended activity leaves the lock screen. Now removes it at once.
  Without it, iOS keeps an ended activity up to four hours.
  """
  @spec finish(String.t(), map(), keyword()) :: result()
  def finish(token, content_state, opts \\ []) when is_binary(token) and is_map(content_state) do
    "end"
    |> aps(content_state, opts)
    |> put(:alert, alert(opts[:alert]))
    |> put(:"dismissal-date", unix(opts[:dismissal_date]))
    |> put(:"relevance-score", opts[:relevance_score])
    |> push(token, opts)
  end

  defp aps(event, content_state, opts) do
    %{
      event: event,
      timestamp: unix(opts[:timestamp] || DateTime.utc_now()),
      "content-state": content_state
    }
  end

  defp push(aps, token, opts) do
    case Config.get().push do
      %{apns: apns} ->
        APNs.live_activity(token, aps, if(opts[:priority] == :low, do: 5, else: 10), apns)

      _ ->
        {:error, :no_apns}
    end
  end

  defp alert(nil), do: nil

  defp alert(alert) when is_map(alert),
    do: Map.reject(%{title: alert[:title], body: alert[:body]}, fn {_k, v} -> is_nil(v) end)

  defp unix(nil), do: nil
  defp unix(%DateTime{} = at), do: DateTime.to_unix(at)

  defp put(map, _key, nil), do: map
  defp put(map, key, value), do: Map.put(map, key, value)
end
