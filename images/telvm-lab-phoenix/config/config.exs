import Config

config :phoenix, :json_library, Jason

config :telvm_lab, TelvmLabWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [ip: {0, 0, 0, 0}, port: 3333],
  server: true,
  render_errors: [formats: [json: TelvmLabWeb.ErrorJSON], layout: false],
  secret_key_base: "telvm_lab_dev_secret_key_base_must_be_64_chars_long_aaaaaaaaaa",
  live_view: [signing_salt: "telvm_sign"]

import_config "#{config_env()}.exs"
