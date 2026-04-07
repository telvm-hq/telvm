defmodule Companion.ClusterNode do
  @moduledoc """
  Behaviour for communicating with remote telvm node agents over HTTP.

  Each Ubuntu host in the cluster runs a lightweight Zig binary (`telvm-node-agent`)
  that exposes `/health`, `/docker/version`, and `/docker/containers`. The companion
  polls these endpoints via Finch; tests swap in `Companion.ClusterNode.Mock`.
  """

  @type base_url :: String.t()
  @type token :: String.t()

  @callback health(base_url(), token()) :: {:ok, map()} | {:error, term()}
  @callback docker_version(base_url(), token()) :: {:ok, map()} | {:error, term()}
  @callback docker_containers(base_url(), token()) :: {:ok, [map()]} | {:error, term()}

  @doc false
  def impl do
    Application.get_env(:companion, :cluster_node_adapter, Companion.ClusterNode.HTTP)
  end
end
