defmodule TelvmLabWeb.Endpoint do
  @moduledoc false
  use Phoenix.Endpoint, otp_app: :telvm_lab

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug TelvmLabWeb.Router
end
