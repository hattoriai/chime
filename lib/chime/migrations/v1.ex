defmodule Chime.Migrations.V1 do
  @moduledoc false
  # The events, the notifications, their deliveries, the preferences and
  # the counts.

  use PhoenixMountable.Migration, description: "Chime's tables"

  def up(ctx) do
    create table(:chime_events, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :notifier, :string, size: 255, null: false
      add :kind, :string, size: 120, null: false
      add :category, :string, size: 120, null: false
      add :data, :map, null: false
      add :actor, :map
      add :workspace, :string, size: 255
      add :group_key, :string, size: 255
      add :key, :string, size: 255
      add :recipients, :integer, null: false, default: 0
      # "sent", or "scheduled" until its time (with its people kept in
      # audience), or "cancelled" before it.
      add :status, :string, size: 16, null: false, default: "sent"
      add :scheduled_at, :utc_datetime_usec
      add :audience, {:array, :string}
      # With the notifier's audience/1: the key of the last person done.
      add :cursor, :string, size: 255
      add :inserted_at, :utc_datetime_usec, null: false
    end

    # One event for each idempotency key. Nulls are distinct, on both.
    create unique_index(:chime_events, [:key], prefix: ctx.prefix)
    create index(:chime_events, [:inserted_at], prefix: ctx.prefix)

    create table(:chime_notifications, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :recipient, :string, size: 255, null: false

      add :event_id,
          references(:chime_events, type: :binary_id, on_delete: :delete_all, prefix: ctx.prefix),
          null: false

      add :kind, :string, size: 120, null: false
      add :category, :string, size: 120, null: false
      add :workspace, :string, size: 255
      add :group_key, :string, size: 255
      # Open to the events of its group, until grouped_until or a read.
      add :grouping, :boolean, null: false, default: false
      add :grouped_until, :utc_datetime_usec
      add :count, :integer, null: false, default: 1
      add :actors, {:array, :map}, null: false, default: []
      add :actor_count, :integer, null: false, default: 0
      add :in_feed, :boolean, null: false, default: true
      add :seen_at, :utc_datetime_usec
      add :read_at, :utc_datetime_usec
      add :archived_at, :utc_datetime_usec
      # Opened from a link of an email or a channel (Chime.link/2).
      add :clicked_at, :utc_datetime_usec
      # The action the person took on it, and when (Chime.act/3).
      add :action, :string, size: 64
      add :acted_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    # The feed, newest first.
    create index(:chime_notifications, [:recipient, :updated_at], prefix: ctx.prefix)
    create index(:chime_notifications, [:recipient, :workspace, :updated_at], prefix: ctx.prefix)
    create index(:chime_notifications, [:event_id], prefix: ctx.prefix)
    create index(:chime_notifications, [:inserted_at], prefix: ctx.prefix)

    # One open group for each person and group key: the events of the
    # group join it.
    create unique_index(:chime_notifications, [:recipient, :group_key],
             where: "grouping",
             name: :chime_notifications_open_group_index,
             prefix: ctx.prefix
           )

    create table(:chime_deliveries, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true

      add :notification_id,
          references(:chime_notifications,
            type: :binary_id,
            on_delete: :delete_all,
            prefix: ctx.prefix
          ),
          null: false

      add :recipient, :string, size: 255, null: false
      add :channel, :string, size: 64, null: false
      add :status, :string, size: 16, null: false
      add :reason, :string, size: 500
      add :ref, :string, size: 255
      add :attempts, :integer, null: false, default: 0
      add :scheduled_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:chime_deliveries, [:notification_id], prefix: ctx.prefix)
    create index(:chime_deliveries, [:recipient, :status], prefix: ctx.prefix)
    create index(:chime_deliveries, [:status, :scheduled_at], prefix: ctx.prefix)

    # One delivery waiting for each notification and channel: the events
    # of a group that join it while it waits go with it.
    create unique_index(:chime_deliveries, [:notification_id, :channel],
             where: "status = 'scheduled'",
             name: :chime_deliveries_scheduled_index,
             prefix: ctx.prefix
           )

    # Each person's devices, for the :push channel: a browser's Web Push
    # subscription, or a phone's APNs or FCM token.
    create table(:chime_devices, primary_key: false, prefix: ctx.prefix) do
      add :id, :binary_id, primary_key: true
      add :recipient, :string, size: 255, null: false
      add :kind, :string, size: 16, null: false
      add :token, :text, null: false
      add :keys, :map
      add :name, :string, size: 255
      add :enabled, :boolean, null: false, default: true
      add :last_used_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create index(:chime_devices, [:recipient], prefix: ctx.prefix)
    # A token is one device, of whoever registered it last.
    create unique_index(:chime_devices, [:kind, :token], prefix: ctx.prefix)

    create table(:chime_preferences, primary_key: false, prefix: ctx.prefix) do
      add :recipient, :string, size: 255, primary_key: true
      # "" for every workspace, else the workspace's own setting.
      add :workspace, :string, size: 255, primary_key: true, default: ""
      add :category, :string, size: 120, primary_key: true
      add :channel, :string, size: 64, primary_key: true
      add :setting, :string, size: 16, null: false
      add :updated_at, :utc_datetime_usec, null: false
    end

    create table(:chime_counts, primary_key: false, prefix: ctx.prefix) do
      add :recipient, :string, size: 255, primary_key: true
      # "" for the whole feed, else a workspace's part of it.
      add :workspace, :string, size: 255, primary_key: true, default: ""
      add :unseen, :integer, null: false, default: 0
      add :unread, :integer, null: false, default: 0
      add :updated_at, :utc_datetime_usec, null: false
    end
  end

  def down(ctx) do
    drop table(:chime_counts, prefix: ctx.prefix)
    drop table(:chime_devices, prefix: ctx.prefix)
    drop table(:chime_preferences, prefix: ctx.prefix)
    drop table(:chime_deliveries, prefix: ctx.prefix)
    drop table(:chime_notifications, prefix: ctx.prefix)
    drop table(:chime_events, prefix: ctx.prefix)
  end
end
