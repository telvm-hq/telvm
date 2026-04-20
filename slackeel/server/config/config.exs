# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :slackeel,
  generators: [timestamp_type: :utc_datetime],
  # __DIR__ is server/config → repo manifest is ../../manifest (slackeel/manifest/models.json)
  manifest_path: Path.expand("../../manifest/models.json", __DIR__),
  preflight_disk_variance: 1.15,
  # Local defaults (edit here; no .env required for OSS / dev)
  preflight_metrics_url: "http://127.0.0.1:9225/preflight/metrics",
  preflight_metrics_token: nil,
  preflight_metrics_timeout_ms: 5_000,
  ollama_base_url: "http://127.0.0.1:11434",
  ollama_chat_timeout_ms: 120_000,
  ollama_pull_timeout_ms: 7_200_000,
  integration_verify_max_parallel: 3,
  integration_verify_retries: 3,
  integration_verify_prompt: "ciao!"

# Configure the endpoint
config :slackeel, SlackeelWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: SlackeelWeb.ErrorHTML, json: SlackeelWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Slackeel.PubSub,
  live_view: [signing_salt: "Y+w9EDj3"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  slackeel: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  slackeel: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Windows / bind mounts: silence symlink warning for colocated JS (see also dev.exs).
config :phoenix_live_view, :colocated_js, disable_symlink_warning: true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
import_config "runtime.exs"
