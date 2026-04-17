import Config

guides_root =
  case System.get_env("TELVM_GUIDES_ROOT") do
    nil -> Path.expand("../../docs/events/diy-pawnshop-electric-cars", __DIR__)
    "" -> Path.expand("../../docs/events/diy-pawnshop-electric-cars", __DIR__)
    p -> p
  end

config :speedeel, :guides_root, guides_root

endpoint_http =
  if System.get_env("PHX_HOST") == "0.0.0.0" do
    [ip: {0, 0, 0, 0}]
  else
    [ip: {127, 0, 0, 1}]
  end

port = String.to_integer(System.get_env("PORT") || "4010")

# File watchers (esbuild/tailwind --watch) and code_reloader often break or hang in
# Docker, especially with bind mounts from Windows hosts — skip so `mix phx.server` binds :4010.
docker? = System.get_env("SPEEDEEL_DOCKER") in ~w(1 true yes)

watchers =
  if docker? do
    []
  else
    [
      esbuild: {Esbuild, :install_and_run, [:speedeel, ~w(--sourcemap=inline --watch)]},
      tailwind: {Tailwind, :install_and_run, [:speedeel, ~w(--watch)]}
    ]
  end

config :speedeel, SpeedeelWeb.Endpoint,
  http: Keyword.put(endpoint_http, :port, port),
  check_origin: false,
  code_reloader: not docker?,
  debug_errors: true,
  secret_key_base: "speedeel_dev_secret_key_base_must_be_at_least_64_characters_long_zzzzzzzz",
  watchers: watchers
