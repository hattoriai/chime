defmodule ChimeTest.Mailer do
  @moduledoc "The mailer of the tests: the emails stay in the test's process."
  use Swoosh.Mailer, otp_app: :chime
end
