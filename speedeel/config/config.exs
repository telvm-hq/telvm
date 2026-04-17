import Config

config :speedeel,
  generators: [timestamp_type: :utc_datetime]

config :speedeel, SpeedeelWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SpeedeelWeb.ErrorHTML, json: SpeedeelWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Speedeel.PubSub,
  live_view: [signing_salt: "speedeel_lv_salt"]

config :esbuild,
  version: "0.25.4",
  speedeel: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

config :tailwind,
  version: "4.1.12",
  speedeel: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

config :phoenix_live_view, :colocated_js, disable_symlink_warning: true

import_config "#{config_env()}.exs"
import_config "runtime.exs"
