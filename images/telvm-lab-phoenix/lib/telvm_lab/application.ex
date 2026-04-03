defmodule TelvmLab.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      TelvmLabWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: TelvmLab.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
