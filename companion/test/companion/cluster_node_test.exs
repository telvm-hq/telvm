defmodule Companion.ClusterNodeTest do
  use ExUnit.Case, async: true

  alias Companion.ClusterNode.Mock

  test "Mock.health/2 returns expected map shape" do
    assert {:ok, %{"hostname" => _, "uptime_s" => _, "agent_version" => _, "docker_reachable" => _}} =
             Mock.health("http://localhost:9100", "tok")
  end

  test "Mock.docker_version/2 returns version map" do
    assert {:ok, %{"Version" => _}} = Mock.docker_version("http://localhost:9100", "tok")
  end

  test "Mock.docker_containers/2 returns list" do
    assert {:ok, []} = Mock.docker_containers("http://localhost:9100", "tok")
  end
end
