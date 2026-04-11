defmodule Companion.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    base = [
      CompanionWeb.Telemetry,
      {Phoenix.PubSub, name: Companion.PubSub},
      Companion.Repo,
      {DNSCluster, query: Application.get_env(:companion, :dns_cluster_query) || :ignore},
      {Finch, name: Companion.Finch, pools: finch_pools()},
      {DynamicSupervisor,
       strategy: :one_for_one, name: Companion.VmLifecycle.RunnerDynamicSupervisor},
      Companion.PreflightServer
    ]

    children =
      base ++
        network_agent_children() ++
        [
          {Companion.GooseHealth, Application.get_env(:companion, Companion.GooseHealth, [])},
          Companion.RetardeelVerifier,
          CompanionWeb.Endpoint
        ]

    opts = [strategy: :rest_for_one, name: Companion.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp network_agent_children do
    url = Application.get_env(:companion, :network_agent_url, "")

    if is_binary(url) and url != "" do
      [Companion.NetworkAgentPoller, Companion.Docker.RemoteVerifier]
    else
      []
    end
  end

  @impl true
  def config_change(changed, _new, removed) do
    CompanionWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp finch_pools do
    sock = Application.get_env(:companion, :docker_socket, "/var/run/docker.sock")

    %{
      :default => [size: 25, count: 1],
      {:http, {:local, sock}} => [
        protocols: [:http1],
        size: 10,
        conn_opts: [
          hostname: "localhost",
          transport_opts: [timeout: 15_000]
        ]
      ]
    }
  end
end
