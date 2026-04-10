defmodule Companion.NetworkAgentPoller do
  @moduledoc """
  Periodic poller for the telvm network agent (PowerShell ICS service on the
  Windows gateway).

  Each tick:
    1. Fetches `/health` and `/ics/hosts` from the network agent.
    2. For every discovered host IP, probes `http://<ip>:9100/health` to check
       whether a Zig `telvm-node-agent` is running on that machine.
    3. Broadcasts a unified `{:network_agent_snapshot, snapshot}` on PubSub so
       `StatusLive` can render a single "LAN hosts" table with both L2/L3
       reachability and application-layer agent status.
  """

  use GenServer
  require Logger

  @default_interval :timer.seconds(30)
  @zig_agent_port 9100
  @zig_agent_token "test123"
  @zig_probe_timeout 4_000

  def topic, do: "network_agent:updates"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

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
    {:ok, %{interval: interval, last_snapshot: nil, last_run_at: nil}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, %{last_snapshot: state.last_snapshot, last_run_at: state.last_run_at}, state}
  end

  @impl true
  def handle_info(:tick, state) do
    try do
      run_tick(state)
    rescue
      e ->
        Logger.error(
          "[NetworkAgentPoller] tick failed: #{Exception.format(:error, e, __STACKTRACE__)}"
        )

        Process.send_after(self(), :tick, state.interval)
        {:noreply, state}
    end
  end

  defp run_tick(state) do
    url = network_agent_url()
    token = network_agent_token()
    adapter = Companion.NetworkAgent.impl()
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    health_result =
      case adapter.health(url, token) do
        {:ok, data} -> %{status: :ok, data: data}
        {:error, reason} -> %{status: :unreachable, data: nil, error: inspect(reason)}
      end

    ics_status =
      case adapter.ics_status(url, token) do
        {:ok, data} -> data
        {:error, _} -> %{}
      end

    raw_hosts =
      case adapter.ics_hosts(url, token) do
        {:ok, data} -> normalize_hosts(Map.get(data, "hosts"))
        {:error, _} -> []
      end

    hosts = probe_zig_agents(raw_hosts)

    snapshot = %{
      url: url,
      checked_at: checked_at,
      health: health_result,
      ics_status: ics_status,
      hosts: hosts,
      host_count: length(hosts)
    }

    ok_count = Enum.count(hosts, &(&1["zig_agent_status"] == "ok"))
    total = length(hosts)
    agent_label = if health_result.status == :ok, do: "ok", else: "unreachable"
    Logger.info("NetworkAgentPoller: agent #{agent_label}, #{total} host(s), #{ok_count} with zig agent")

    Phoenix.PubSub.broadcast(Companion.PubSub, topic(), {:network_agent_snapshot, snapshot})

    Process.send_after(self(), :tick, state.interval)
    {:noreply, %{state | last_snapshot: snapshot, last_run_at: checked_at}}
  end

  defp normalize_hosts(raw), do: Companion.NetworkAgentHosts.normalize(raw)

  defp probe_zig_agents(hosts) when is_list(hosts) do
    hosts
    |> Task.async_stream(
      fn host ->
        ip = host["ip"]

        if ip && unicast_ip?(ip) do
          base_url = "http://#{ip}:#{@zig_agent_port}"

          case probe_health(base_url) do
            {:ok, health_data} ->
              host
              |> Map.put("zig_agent_status", "ok")
              |> Map.put("zig_agent_health", health_data)

            {:error, _reason} ->
              host
              |> Map.put("zig_agent_status", "unreachable")
              |> Map.put("zig_agent_health", nil)
          end
        else
          host
          |> Map.put("zig_agent_status", "n/a")
          |> Map.put("zig_agent_health", nil)
        end
      end,
      timeout: @zig_probe_timeout + 2_000,
      on_timeout: :kill_task
    )
    |> Enum.map(fn
      {:ok, result} -> result
      {:exit, _} -> %{"zig_agent_status" => "timeout", "zig_agent_health" => nil}
    end)
  end

  defp probe_health(base_url) do
    url = base_url <> "/health"

    headers =
      if @zig_agent_token != "" do
        [{"authorization", "Bearer #{@zig_agent_token}"}]
      else
        []
      end

    req = Finch.build(:get, url, headers)

    case Finch.request(req, Companion.Finch, receive_timeout: @zig_probe_timeout) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp unicast_ip?(ip) when is_binary(ip) do
    not String.starts_with?(ip, "224.") and
      not String.starts_with?(ip, "239.") and
      not String.starts_with?(ip, "255.") and
      ip != "0.0.0.0"
  end

  defp network_agent_url do
    Application.get_env(:companion, :network_agent_url, "http://host.docker.internal:9225")
  end

  defp network_agent_token do
    Application.get_env(:companion, :network_agent_token, "")
  end
end
