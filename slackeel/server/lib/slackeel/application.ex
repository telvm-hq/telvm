defmodule Slackeel.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    :ok = Slackeel.Ollama.ProbeMetrics.init_table()

    children = [
      SlackeelWeb.Telemetry,
      Slackeel.Repo,
      {Finch, name: Slackeel.Finch, pools: %{default: [size: 16]}},
      {DNSCluster, query: Application.get_env(:slackeel, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Slackeel.PubSub},
      {Task.Supervisor, name: Slackeel.Ollama.HotTaskSupervisor},
      Slackeel.Ollama.HotRegistry,
      # Start to serve requests, typically the last entry
      SlackeelWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Slackeel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SlackeelWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
