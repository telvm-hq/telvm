import Config

config :speedeel, :guides_root,
  Path.expand("../../docs/events/diy-pawnshop-electric-cars", __DIR__)

config :speedeel, SpeedeelWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4011],
  secret_key_base: "speedeel_test_secret_key_base_must_be_at_least_64_characters_long_zzzz",
  server: false

config :logger, level: :warning
