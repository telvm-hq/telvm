import Config

# Avoid hitting a real metrics agent during tests (use :disksup path in Preflight).
config :slackeel, preflight_metrics_url: nil

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :slackeel, SlackeelWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "/d/RmL9GTq75ij+vSMGJPIGc7aaqnYVB5isSO9zLxoZ07/O4IT1Vq1JUrx24yCoZ",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
