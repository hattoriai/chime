defmodule Mix.Tasks.Chime.Gen.Vapid do
  @shortdoc "Generates the VAPID keys of the app's Web Push"

  @moduledoc """
  Generates a pair of VAPID keys, for `:web` of the `:push` option of
  `Chime.Config`:

      $ mix chime.gen.vapid

  Keep the private key as a secret of the app's (an environment
  variable), and give both to Chime in `config/runtime.exs`. Make them
  once: browsers subscribed with the public key stop getting pushes when
  it changes.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    {public, private} = :crypto.generate_key(:ecdh, :prime256v1)

    Mix.shell().info("""
    public_key:  #{Base.url_encode64(public, padding: false)}
    private_key: #{Base.url_encode64(private, padding: false)}
    """)
  end
end
