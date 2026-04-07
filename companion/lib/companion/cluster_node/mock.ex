defmodule Companion.ClusterNode.Mock do
  @moduledoc false
  @behaviour Companion.ClusterNode

  @impl true
  def health(_base_url, _token) do
    {:ok,
     %{
       "hostname" => "mock-node",
       "uptime_s" => 86400,
       "agent_version" => "0.1.0",
       "docker_reachable" => true
     }}
  end

  @impl true
  def docker_version(_base_url, _token) do
    {:ok, %{"Version" => "27.0.0", "ApiVersion" => "1.46"}}
  end

  @impl true
  def docker_containers(_base_url, _token) do
    {:ok, []}
  end
end
