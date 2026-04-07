defmodule Companion.ClusterNodePollerTest do
  use ExUnit.Case, async: false

  alias Companion.ClusterNodePoller

  setup do
    prev_nodes = Application.get_env(:companion, :cluster_nodes)
    prev_token = Application.get_env(:companion, :cluster_token)
    prev_adapter = Application.get_env(:companion, :cluster_node_adapter)

    Application.put_env(:companion, :cluster_nodes, [
      %{url: "http://fake:9100", label: "test-node"}
    ])

    Application.put_env(:companion, :cluster_token, "test-token")
    Application.put_env(:companion, :cluster_node_adapter, Companion.ClusterNode.Mock)

    on_exit(fn ->
      if prev_nodes, do: Application.put_env(:companion, :cluster_nodes, prev_nodes), else: Application.delete_env(:companion, :cluster_nodes)
      if prev_token, do: Application.put_env(:companion, :cluster_token, prev_token), else: Application.delete_env(:companion, :cluster_token)
      if prev_adapter, do: Application.put_env(:companion, :cluster_node_adapter, prev_adapter), else: Application.delete_env(:companion, :cluster_node_adapter)
    end)

    :ok
  end

  test "poller broadcasts cluster_snapshot on PubSub" do
    Phoenix.PubSub.subscribe(Companion.PubSub, ClusterNodePoller.topic())

    {:ok, pid} = start_supervised({ClusterNodePoller, interval: 100})

    assert_receive {:cluster_snapshot, results}, 5_000
    assert is_list(results)
    assert length(results) == 1

    [node] = results
    assert node.label == "test-node"
    assert node.status == :ok
    assert node.health["hostname"] == "mock-node"

    GenServer.stop(pid)
  end

  test "snapshot/0 returns last results after a tick" do
    {:ok, pid} = start_supervised({ClusterNodePoller, interval: 100})

    Process.sleep(300)

    snap = ClusterNodePoller.snapshot()
    assert is_map(snap)
    assert is_list(snap.last_results)
    assert length(snap.last_results) == 1

    GenServer.stop(pid)
  end
end
