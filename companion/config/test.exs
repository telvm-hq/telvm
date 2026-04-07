import Config

# Database: default is local Postgres on localhost. For tests inside Docker Compose, set
# TEST_DATABASE_URL (recommended), e.g. postgres://postgres:postgres@db:5432/companion_test
#
# DATABASE_URL is also honored when TEST_DATABASE_URL is unset (e.g. some CI jobs). Prefer
# TEST_DATABASE_URL in Compose so it never points at the dev database by mistake.
#
# MIX_TEST_PARTITION can be used for partitioned test databases on CI.
test_repo_url =
  case System.get_env("TEST_DATABASE_URL") do
    u when is_binary(u) and u != "" ->
      u

    _ ->
      case System.get_env("DATABASE_URL") do
        u when is_binary(u) and u != "" -> u
        _ -> nil
      end
  end

repo_base = [
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2
]

if test_repo_url do
  config :companion, Companion.Repo, Keyword.put(repo_base, :url, test_repo_url)
else
  config :companion,
         Companion.Repo,
         Keyword.merge(repo_base,
           username: "postgres",
           password: "postgres",
           hostname: "localhost",
           database: "companion_test#{System.get_env("MIX_TEST_PARTITION")}"
         )
end

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :companion, CompanionWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "E4U30ibXoa6KhVymXv5MWID902mH+yt9XRFxPo9DoQS/JZ+jdjLF2L6zqm8xW1ek",
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

config :companion, :docker_adapter, Companion.Docker.Mock
config :companion, :cluster_node_adapter, Companion.ClusterNode.Mock

config :companion, Companion.GooseHealth, enabled: false

# VM manager pre-flight health probes use real Finch by default; stub in tests so the runner stays deterministic.
config :companion, :vm_manager_preflight_http_fun, fn _url ->
  {:ok, %{status: 200, latency_ms: 0}}
end
