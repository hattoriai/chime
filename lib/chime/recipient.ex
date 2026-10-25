defmodule Chime.Recipient do
  @moduledoc """
  A person who gets notifications, as the app's `Chime.Resolver` says:

    * `:id` - a string unique among the app's people: `"user:42"`. The
      notifications, the preferences and the counts are kept by it.
    * `:email` - where the `:email` channel and the digests write, or nil.
    * `:name` - for the emails' `To:`.
    * `:locale` - the language the app speaks to them, for the notifier's
      words (`Gettext.with_locale/3`).
    * `:time_zone` - an IANA time zone (`"Europe/Lisbon"`), for the hour
      of the digests. UTC without one, or without a time zone database.
    * `:data` - anything else the app's notifiers and channels need: a
      phone number, a Telegram chat, the user itself.
  """

  @enforce_keys [:id]
  defstruct [:id, :email, :name, :locale, :time_zone, data: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t() | nil,
          name: String.t() | nil,
          locale: String.t() | nil,
          time_zone: String.t() | nil,
          data: term()
        }
end
