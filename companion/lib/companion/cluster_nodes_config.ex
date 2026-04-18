defmodule Companion.ClusterNodesConfig do
  @moduledoc """
  Reads a static cluster node list from application env (`:cluster_nodes`, `:cluster_token`).

  **`Companion.ClusterNodePoller` is not supervised** and nothing in `runtime.exs` maps
  `TELVM_CLUSTER_*` env vars into these keys today — tests set them with
  `Application.put_env/3`. For shipped LAN discovery use **`NetworkAgentPoller`** instead;
  see **docs/wiki/GROUND_TRUTH.md**.
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
