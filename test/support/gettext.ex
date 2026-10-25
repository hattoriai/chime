defmodule ChimeTest.Gettext do
  @moduledoc "The app's Gettext of the tests, with Chime's words in Portuguese."
  use Gettext.Backend, otp_app: :chime, priv: "test/support/gettext"
end
