defmodule CompanionWeb.MachineController do
  @moduledoc """
  Agent control-plane API for telvm sandboxes.

  All endpoints live under `/telvm/api/`. No authentication in v0.1.0 — local
  network trust only. Each response includes `proxy_urls` derived from PortScanner
  so agents can reach running services without opening a browser.

  Endpoint summary:

      GET    /telvm/api/machines              list warm lab containers
      GET    /telvm/api/machines/:id          single machine detail
      POST   /telvm/api/machines              create + start container
      POST   /telvm/api/machines/:id/exec     run a command inside a container
      DELETE /telvm/api/machines/:id          stop + remove container
      GET    /telvm/api/stream                SSE stream of state changes
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
end
