defmodule Companion.ClusterNodePoller do
  @moduledoc """
  Periodic health poller for remote telvm node agents.

  Ticks every `interval_ms` (default 30s), calls `GET /health` on each configured
  node via `Companion.ClusterNode.impl()`, and broadcasts results on PubSub so
  LiveView or other subscribers render cluster status without making their own HTTP calls.

  Exposes `snapshot/0` for IEx exploration:

      iex> Companion.ClusterNodePoller.snapshot()
  """

  use GenServer
  require Logger

  alias Companion.ClusterNodesConfig

  @default_interval :timer.seconds(30)

  @doc "PubSub topic for `{:cluster_snapshot, results}` messages."
  def topic, do: "cluster_nodes:updates"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Returns last poll results or `{:error, :not_running}`."
  def snapshot do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      _pid -> GenServer.call(__MODULE__, :snapshot)
    end
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    send(self(), :tick)
    {:ok, %{interval: interval, last_results: [], last_run_at: nil}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, %{last_results: state.last_results, last_run_at: state.last_run_at}, state}
  end

  @impl true
  def handle_info(:tick, state) do
    nodes = ClusterNodesConfig.nodes()
    token = ClusterNodesConfig.token()
    adapter = Companion.ClusterNode.impl()

    results =
      nodes
      |> Task.async_stream(
        fn node ->
          checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

          case adapter.health(node.url, token) do
            {:ok, data} ->
              %{
                label: node.label,
                url: node.url,
                status: :ok,
                health: data,
                error: nil,
                checked_at: checked_at
              }

            {:error, reason} ->
              %{
                label: node.label,
                url: node.url,
                status: :unreachable,
                health: nil,
                error: inspect(reason),
                checked_at: checked_at
              }
          end
        end,
        timeout: 10_000,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} ->
          result

        {:exit, _reason} ->
          %{label: "?", url: "?", status: :timeout, health: nil, error: "timeout", checked_at: DateTime.utc_now() |> DateTime.truncate(:second)}
      end)

    run_at = DateTime.utc_now() |> DateTime.truncate(:second)

    ok = Enum.count(results, &(&1.status == :ok))
    total = length(results)
    Logger.info("ClusterNodePoller: #{ok}/#{total} nodes reachable")

    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      topic(),
      {:cluster_snapshot, results}
    )

    Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | last_results: results, last_run_at: run_at}}
  end
end
