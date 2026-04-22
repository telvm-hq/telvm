import Config

# Loaded after `config/#{env}.exs`. Optional overrides (e.g. Docker Compose) — no .env required.

case System.get_env("SLACKEEL_MANIFEST_PATH") do
  p when is_binary(p) and p != "" -> config(:slackeel, manifest_path: p)
  _ -> :ok
end

case System.get_env("SLACKEEL_OLLAMA_BASE_URL") do
  url when is_binary(url) and url != "" -> config(:slackeel, ollama_base_url: url)
  _ -> :ok
end

# Pre-flight metrics URL (telvm-network-agent). Empty string disables HTTP metrics (local disk only).
case System.get_env("SLACKEEL_PREFLIGHT_METRICS_URL") do
  nil -> :ok
  "" -> config(:slackeel, preflight_metrics_url: nil)
  url when is_binary(url) -> config(:slackeel, preflight_metrics_url: url)
end

# Production-only endpoint for release / Docker — no secrets, no .env.
# Same public port as dev (:4020) so Slackeel stays off :4000 / :4010 (Telvm Companion / Speedeel).

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: postgresql://USER:PASS@HOST:5432/DATABASE
      """

  config :slackeel, Slackeel.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  config :slackeel, SlackeelWeb.Endpoint,
    server: true,
    secret_key_base: "yyU5ko0EuQLuMvkpbHN562mMhxEOKo0uEj3kJM+L5ZCzkvJi+or7UDhKqcshCkwK",
    url: [host: "localhost", port: 4020, scheme: "http"],
    http: [port: 4020, ip: {0, 0, 0, 0, 0, 0, 0, 0}],
    check_origin: false

  config :slackeel, :dns_cluster_query, :ignore
end
