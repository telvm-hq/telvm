defmodule CompanionWeb.MachineController do
  @moduledoc """
  Agent control-plane API for telvm sandboxes.

  All endpoints live under `/telvm/api/`. No authentication in v0.1.0 — local
  network trust only. Each response includes `proxy_urls` derived from PortScanner
  so agents can reach running services without opening a browser.

  Endpoint summary:

      GET    /telvm/api/machines                 list warm lab containers
      GET    /telvm/api/machines/:id/stats       one-shot resource stats (optional ?raw=1)
      GET    /telvm/api/machines/:id/logs        one-shot stdout/stderr log tail (optional ?tail=)
      GET    /telvm/api/machines/:id             single machine detail
      POST   /telvm/api/machines                 create + start container (optional `env` for container Env)
      POST   /telvm/api/machines/:id/exec        run a command inside a container
      POST   /telvm/api/machines/:id/restart     Engine restart (optional ?t=seconds)
      POST   /telvm/api/machines/:id/pause       freeze cgroup (not a reload/restart)
      POST   /telvm/api/machines/:id/unpause     resume from pause
      DELETE /telvm/api/machines/:id             stop + remove container
      GET    /telvm/api/stream                   SSE stream of state changes
  """

  use CompanionWeb, :controller

  alias Companion.Docker
  alias Companion.VmLifecycle
  alias Companion.VmLifecycle.PortScanner
  alias Companion.VmLifecycle.SoakRunner

  @lab_label "telvm.vm_manager_lab"
  @ephemeral_threshold 32_768

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines
  # ---------------------------------------------------------------------------

  def index(conn, _params) do
    docker = Docker.impl()

    case docker.container_list(filters: %{"label" => ["#{@lab_label}=true"]}) do
      {:ok, containers} ->
        machines = Enum.map(containers, &build_machine(docker, &1))
        json(conn, %{machines: machines})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Docker error: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines/:id
  # ---------------------------------------------------------------------------

  def show(conn, %{"id" => id}) do
    docker = Docker.impl()

    case docker.container_inspect(id) do
      {:ok, info} ->
        machine = build_machine_from_inspect(docker, info)
        json(conn, %{machine: machine})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Machine not found"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Docker error: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines
  # ---------------------------------------------------------------------------

  def create(conn, params) do
    docker = Docker.impl()

    overrides =
      []
      |> maybe_put_kw(:image, params["image"])
      |> maybe_put_kw(:workspace, params["workspace"])
      |> maybe_put_kw(:container_cmd, params["cmd"])
      |> maybe_put_kw_bool(:use_image_default_cmd, params["use_image_cmd"])
      |> maybe_put_container_env(params["env"])

    cfg = VmLifecycle.manager_preflight_config(overrides)
    name = "telvm-vm-mgr-" <> Integer.to_string(:erlang.unique_integer([:positive]))
    attrs = VmLifecycle.lab_container_create_attrs(cfg, name)

    with {:ok, cid} <- docker.container_create(attrs),
         :ok <- docker.container_start(cid, []) do
      case docker.container_inspect(cid) do
        {:ok, info} ->
          machine = build_machine_from_inspect(docker, info)

          conn
          |> put_status(201)
          |> json(%{machine: machine})

        {:error, _} ->
          conn
          |> put_status(201)
          |> json(%{machine: %{id: cid, name: name, status: "starting"}})
      end
    else
      {:error, reason} ->
        conn
        |> put_status(422)
        |> json(%{error: "Failed to create machine: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines/:id/exec
  # ---------------------------------------------------------------------------

  def exec(conn, %{"id" => id} = params) do
    docker = Docker.impl()
    cmd = params["cmd"]
    workdir = params["workdir"]

    unless is_list(cmd) and Enum.all?(cmd, &is_binary/1) do
      conn
      |> put_status(400)
      |> json(%{error: "cmd must be a non-empty list of strings"})
    else
      opts = if workdir, do: [workdir: workdir], else: []

      case docker.container_exec_with_exit(id, cmd, opts) do
        {:ok, %{stdout: stdout, exit_code: exit_code}} ->
          json(conn, %{exit_code: exit_code, stdout: stdout, stderr: ""})

        {:error, :not_found} ->
          conn
          |> put_status(404)
          |> json(%{error: "Machine not found"})

        {:error, reason} ->
          conn
          |> put_status(502)
          |> json(%{error: "Exec failed: #{inspect(reason)}"})
      end
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines/:id/restart
  # ---------------------------------------------------------------------------

  def restart(conn, %{"id" => id}) do
    docker = Docker.impl()
    t = restart_stop_timeout(conn)

    case docker.container_restart(id, timeout_sec: t) do
      :ok ->
        case docker.container_inspect(id) do
          {:ok, info} ->
            machine = build_machine_from_inspect(docker, info)
            json(conn, %{machine: machine})

          {:error, _} ->
            json(conn, %{ok: true})
        end

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Machine not found"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Failed to restart machine: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines/:id/stats
  # ---------------------------------------------------------------------------

  def stats(conn, %{"id" => id} = params) do
    docker = Docker.impl()
    raw? = stats_raw_param?(params["raw"])

    case docker.container_stats(id) do
      {:ok, map} when raw? ->
        json(conn, %{stats: map})

      {:ok, map} ->
        json(conn, %{stats: trim_container_stats(map)})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Machine not found"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Stats failed: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines/:id/logs
  # ---------------------------------------------------------------------------

  def logs(conn, %{"id" => id} = params) do
    docker = Docker.impl()
    tail = logs_tail_param(params["tail"])

    case docker.container_logs(id, tail: tail) do
      {:ok, text} ->
        json(conn, %{logs: text})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Machine not found"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Logs failed: #{inspect(reason)}"})
    end
  end

  defp logs_tail_param(nil), do: 500

  defp logs_tail_param(raw) when is_binary(raw) do
    case Integer.parse(raw) do
      {n, _} -> min(max(n, 1), 10_000)
      :error -> 500
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines/:id/pause
  # ---------------------------------------------------------------------------

  def pause(conn, %{"id" => id}) do
    case Docker.impl().container_pause(id) do
      :ok ->
        json(conn, %{ok: true})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Machine not found"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Pause failed: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines/:id/unpause
  # ---------------------------------------------------------------------------

  def unpause(conn, %{"id" => id}) do
    case Docker.impl().container_unpause(id) do
      :ok ->
        json(conn, %{ok: true})

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Machine not found"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Unpause failed: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /telvm/api/machines/:id
  # ---------------------------------------------------------------------------

  def delete(conn, %{"id" => id}) do
    docker = Docker.impl()

    _ = docker.container_stop(id, timeout_sec: 5)

    case docker.container_remove(id, force: true) do
      :ok ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "Machine not found"})

      {:error, reason} ->
        conn
        |> put_status(502)
        |> json(%{error: "Failed to remove machine: #{inspect(reason)}"})
    end
  end

  # ---------------------------------------------------------------------------
  # GET /telvm/api/stream  (Server-Sent Events)
  # ---------------------------------------------------------------------------

  def stream(conn, _params) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("x-accel-buffering", "no")
      |> send_chunked(200)

    Phoenix.PubSub.subscribe(Companion.PubSub, SoakRunner.topic())
    Phoenix.PubSub.subscribe(Companion.PubSub, VmLifecycle.topic())

    schedule_snapshot()
    stream_loop(conn)
  end

  # ---------------------------------------------------------------------------
  # SSE loop
  # ---------------------------------------------------------------------------

  defp stream_loop(conn) do
    receive do
      :snapshot ->
        docker = Docker.impl()

        machines =
          case docker.container_list(filters: %{"label" => ["#{@lab_label}=true"]}) do
            {:ok, containers} -> Enum.map(containers, &build_machine(docker, &1))
            {:error, _} -> []
          end

        payload = Jason.encode!(%{machines: machines})
        schedule_snapshot()

        case send_sse(conn, "machines_snapshot", payload) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      {:soak_monitor, {:session, :clear}} ->
        case send_sse(conn, "soak_session", Jason.encode!(%{phase: nil})) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      {:soak_monitor, {:session, %{container_id: cid, phase: phase}}} ->
        payload = Jason.encode!(%{container_id: cid, phase: phase})

        case send_sse(conn, "soak_session", payload) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      {:soak_monitor, {:done, result, meta}} ->
        payload =
          Jason.encode!(%{
            result: format_result(result),
            stability_probes: Map.get(meta, :stability_probes, %{})
          })

        case send_sse(conn, "soak_done", payload) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      {:vm_manager_preflight, {:session, :clear}} ->
        case send_sse(conn, "preflight_session", Jason.encode!(%{phase: nil})) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      {:vm_manager_preflight, {:session, %{container_id: cid, phase: phase}}} ->
        payload = Jason.encode!(%{container_id: cid, phase: phase})

        case send_sse(conn, "preflight_session", payload) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      {:vm_manager_preflight, {:done, result}} ->
        payload = Jason.encode!(%{result: format_result(result)})

        case send_sse(conn, "preflight_done", payload) do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end

      _ ->
        stream_loop(conn)
    after
      30_000 ->
        case chunk(conn, ": keepalive\n\n") do
          {:ok, conn} -> stream_loop(conn)
          {:error, _} -> conn
        end
    end
  end

  defp send_sse(conn, event, data) do
    case chunk(conn, "event: #{event}\ndata: #{data}\n\n") do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, reason}
    end
  end

  defp schedule_snapshot do
    Process.send_after(self(), :snapshot, 5_000)
  end

  defp format_result(:ok), do: "ok"
  defp format_result({:error, reason}), do: "error: #{inspect(reason)}"
  defp format_result(other), do: inspect(other)

  # ---------------------------------------------------------------------------
  # Machine data helpers
  # ---------------------------------------------------------------------------

  defp build_machine(_docker, container_map) do
    id = container_map["Id"]
    name = extract_name(container_map["Names"])
    image = container_map["Image"]
    status = container_map["State"] || container_map["Status"] || "unknown"
    created = container_map["Created"]

    all_ports =
      if status == "running" do
        case PortScanner.scan_ports(id) do
          {:ok, p} -> p
          {:error, _} -> []
        end
      else
        []
      end

    proxy_ports = Enum.filter(all_ports, &(&1 < @ephemeral_threshold))

    %{
      id: id,
      name: name,
      image: image,
      status: status,
      created_at: format_created(created),
      ports: proxy_ports,
      proxy_urls: build_proxy_urls(name, proxy_ports)
    }
  end

  defp build_machine_from_inspect(_docker, info) do
    id = info["Id"]

    name =
      info["Name"] |> then(fn n -> if is_binary(n), do: String.trim_leading(n, "/"), else: "" end)

    image = get_in(info, ["Config", "Image"]) || ""
    status = get_in(info, ["State", "Status"]) || "unknown"
    created = info["Created"]

    all_ports =
      if status == "running" do
        case PortScanner.scan_ports(id) do
          {:ok, p} -> p
          {:error, _} -> []
        end
      else
        []
      end

    proxy_ports = Enum.filter(all_ports, &(&1 < @ephemeral_threshold))

    %{
      id: id,
      name: name,
      image: image,
      status: status,
      created_at: created,
      ports: proxy_ports,
      proxy_urls: build_proxy_urls(name, proxy_ports)
    }
  end

  defp extract_name([n | _]), do: String.trim_leading(n, "/")
  defp extract_name(_), do: ""

  defp format_created(nil), do: nil

  defp format_created(unix) when is_integer(unix) do
    case DateTime.from_unix(unix) do
      {:ok, dt} -> DateTime.to_iso8601(dt)
      _ -> nil
    end
  end

  defp format_created(str) when is_binary(str), do: str

  defp build_proxy_urls(name, ports) do
    Enum.map(ports, fn port ->
      "http://localhost:4000/app/#{name}/port/#{port}/"
    end)
  end

  defp maybe_put_kw(kw, _key, nil), do: kw
  defp maybe_put_kw(kw, _key, ""), do: kw
  defp maybe_put_kw(kw, key, value), do: Keyword.put(kw, key, value)

  defp maybe_put_kw_bool(kw, _key, nil), do: kw
  defp maybe_put_kw_bool(kw, key, value) when is_boolean(value), do: Keyword.put(kw, key, value)
  defp maybe_put_kw_bool(kw, key, "true"), do: Keyword.put(kw, key, true)
  defp maybe_put_kw_bool(kw, key, "false"), do: Keyword.put(kw, key, false)
  defp maybe_put_kw_bool(kw, _key, _), do: kw

  defp maybe_put_container_env(kw, nil), do: kw
  defp maybe_put_container_env(kw, env) when is_list(env) do
    pairs =
      Enum.flat_map(env, fn
        %{"name" => k, "value" => v} when is_binary(k) ->
          [{k, to_string(v)}]

        s when is_binary(s) ->
          case String.split(s, "=", parts: 2) do
            [k, v] -> [{k, v}]
            _ -> []
          end

        _ ->
          []
      end)

    case pairs do
      [] -> kw
      _ -> Keyword.put(kw, :container_env, pairs)
    end
  end

  defp maybe_put_container_env(kw, _), do: kw

  defp restart_stop_timeout(conn) do
    case conn.query_params["t"] do
      nil ->
        10

      "" ->
        10

      s when is_binary(s) ->
        case Integer.parse(s) do
          {n, _} when n >= 0 and n <= 300 -> n
          _ -> 10
        end

      _ ->
        10
    end
  end

  defp stats_raw_param?(v) when v in [true, "true", "1", 1], do: true
  defp stats_raw_param?(_), do: false

  defp trim_container_stats(raw) when is_map(raw) do
    %{
      cpu_percent: cpu_percent_from_engine_stats(raw),
      memory_usage_bytes: get_in(raw, ["memory_stats", "usage"]),
      memory_limit_bytes: get_in(raw, ["memory_stats", "limit"]),
      network_rx_bytes: sum_network_bytes(raw, "rx_bytes"),
      network_tx_bytes: sum_network_bytes(raw, "tx_bytes")
    }
  end

  defp cpu_percent_from_engine_stats(%{"cpu_stats" => cpu, "precpu_stats" => pre})
       when is_map(cpu) and is_map(pre) do
    cpu_total = get_in(cpu, ["cpu_usage", "total_usage"]) || 0
    pre_total = get_in(pre, ["cpu_usage", "total_usage"]) || 0
    cpu_delta = cpu_total - pre_total

    sys = cpu["system_cpu_usage"] || 0
    pre_sys = pre["system_cpu_usage"] || 0
    system_delta = sys - pre_sys

    n = cpu["online_cpus"] || 1

    if system_delta > 0 and cpu_delta >= 0 do
      Float.round(cpu_delta / system_delta * n * 100.0, 2)
    else
      nil
    end
  end

  defp cpu_percent_from_engine_stats(_), do: nil

  defp sum_network_bytes(raw, key) when key in ["rx_bytes", "tx_bytes"] do
    nets = raw["networks"]

    if is_map(nets) do
      Enum.reduce(nets, 0, fn {_iface, m}, acc ->
        v = if is_map(m), do: Map.get(m, key) || 0, else: 0
        acc + v
      end)
    else
      0
    end
  end
end
