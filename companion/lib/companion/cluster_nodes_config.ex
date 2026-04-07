defmodule Companion.ClusterNodesConfig do
  @moduledoc """
  Reads the configured cluster node list from application env.

  Set `TELVM_CLUSTER_NODES` (JSON array) and `TELVM_CLUSTER_TOKEN` in `.env` /
  `docker-compose.yml`; `config/runtime.exs` parses them into
  `config :companion, :cluster_nodes` and `config :companion, :cluster_token`.
  """

  @spec nodes() :: [%{url: String.t(), label: String.t()}]
  def nodes do
    Application.get_env(:companion, :cluster_nodes, [])
  end

  @spec token() :: String.t()
  def token do
    Application.get_env(:companion, :cluster_token, "")
  end

  @spec configured?() :: boolean()
  def configured? do
    nodes() != []
  end
end
