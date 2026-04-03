import Config

if config_env() == :prod do
  port = String.to_integer(System.get_env("PORT") || "3333")

  config :telvm_lab, TelvmLabWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: port]
end
