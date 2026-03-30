defmodule Companion.VmLifecycle.Logic do
  @moduledoc false

  alias Companion.VmLifecycle

  def run(overrides \\ []) when is_list(overrides) do
    result =
      try do
        docker = Companion.Docker.impl()
        cfg = VmLifecycle.manager_preflight_config(overrides)

        narrate(
          "Starting VM manager pre-flight: ephemeral workload on the Compose bridge network."
        )

        if overrides != [] do
          narrate(
            "Run overrides: image=#{cfg[:image]}, use_image_default_cmd=#{cfg[:use_image_default_cmd]}"
          )
        end

        {cid, script_result} =
          case create_lab_container(docker, cfg) do
            {:ok, id} ->
              broadcast_preflight_session(%{container_id: id, phase: :preflight})
              {id, run_script(docker, cfg, id)}

            {:error, reason} ->
              engine_line("container_create failed: #{inspect(reason)}")
              {nil, {:error, reason}}
          end

        if cid do
          narrate("Tearing down lab container.")
          cleanup(docker, cfg, cid)
        end

        case script_result do
          :ok -> narrate("VM manager pre-flight passed: Engine lifecycle + HTTP probe succeeded.")
          {:error, reason} -> narrate("VM manager pre-flight failed: #{inspect(reason)}.")
        end

        script_result
      rescue
        e -> {:error, Exception.message(e)}
      end

    broadcast_preflight_session(:clear)

    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      VmLifecycle.topic(),
      {:vm_manager_preflight, {:done, result}}
    )

    result
  end

  defp create_lab_container(docker, cfg) do
    name = "telvm-vm-mgr-" <> Integer.to_string(:erlang.unique_integer([:positive]))
    attrs = VmLifecycle.lab_container_create_attrs(cfg, name)
    engine_line("POST /containers/create name=#{name} image=#{cfg[:image]}")

    case docker.container_create(attrs) do
      {:ok, id} ->
        engine_line("created id=#{short_id(id)}")
        {:ok, id}

      other ->
        other
    end
  end

  defp run_script(docker, cfg, id) do
    with :ok <- start_and_log(docker, id),
         :ok <- wait_running(docker, id, cfg) do
      broadcast_preflight_session(%{container_id: id, phase: :probe})

      with :ok <- health_window(cfg),
           :ok <- pause_and_log(docker, id),
           :ok <- unpause_and_log(docker, id) do
        :ok
      end
    end
  end

  defp start_and_log(docker, id) do
    engine_line("POST /containers/#{short_id(id)}/start")

    case docker.container_start(id, []) do
      :ok ->
        engine_line("start -> ok")
        :ok

      {:error, _} = e ->
        engine_line("start -> #{inspect(e)}")
        e
    end
  end

  defp wait_running(docker, id, cfg) do
    deadline = System.monotonic_time(:millisecond) + cfg[:wait_running_timeout_ms]
    wait_running_loop(docker, id, deadline)
  end

  defp wait_running_loop(docker, id, deadline) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      engine_line("inspect: timeout waiting for running")
      {:error, :wait_running_timeout}
    else
      case docker.container_inspect(id) do
        {:ok, %{"State" => %{"Status" => "running"}}} ->
          engine_line("inspect State.Status=running (authoritative)")
          :ok

        {:ok, %{"State" => %{"Status" => status}}} ->
          engine_line("inspect State.Status=#{status}, retry…")
          Process.sleep(300)
          wait_running_loop(docker, id, deadline)

        {:error, _} = e ->
          engine_line("inspect -> #{inspect(e)}")
          e
      end
    end
  end

  defp health_window(cfg) do
    port = cfg[:exposed_port]
    path = cfg[:http_probe_path]
    host = cfg[:dns_alias]
    url = "http://#{host}:#{port}#{path}"

    narrate("Health window: probing #{url} (~#{cfg[:health_window_ms]}ms).")

    deadline = System.monotonic_time(:millisecond) + cfg[:health_window_ms]
    health_loop(url, deadline, cfg[:health_probe_interval_ms], false)
  end

  defp health_loop(url, deadline, interval, saw_200) do
    now = System.monotonic_time(:millisecond)

    if now >= deadline do
      if saw_200 do
        narrate("At least one HTTP probe returned 200 inside the window.")
        :ok
      else
        engine_line("probe: no successful response before window end")
        {:error, :health_probe_failed}
      end
    else
      case http_probe(url) do
        {:ok, %{status: status, latency_ms: ms}} ->
          engine_line("GET #{url} -> #{status} (#{ms}ms)")
          saw_200 = saw_200 or status == 200
          Process.sleep(min(interval, max(deadline - now, 0)))
          health_loop(url, deadline, interval, saw_200)

        {:error, reason} ->
          engine_line("GET #{url} -> error #{inspect(reason)}")
          Process.sleep(min(interval, max(deadline - now, 0)))
          health_loop(url, deadline, interval, saw_200)
      end
    end
  end

  defp http_probe(url) do
    fun =
      case Application.get_env(:companion, :vm_manager_preflight_http_fun) do
        nil -> Application.get_env(:companion, :vm_certificate_http_fun)
        f -> f
      end

    case fun do
      f when is_function(f, 1) ->
        f.(url)

      _ ->
        Companion.VmLifecycle.HttpProbe.get(url)
    end
  end

  defp pause_and_log(docker, id) do
    engine_line("POST /containers/#{short_id(id)}/pause")

    case docker.container_pause(id) do
      :ok ->
        log_inspect_status(docker, id, "after pause")
        :ok

      {:error, _} = e ->
        engine_line("pause -> #{inspect(e)}")
        e
    end
  end

  defp unpause_and_log(docker, id) do
    engine_line("POST /containers/#{short_id(id)}/unpause")

    case docker.container_unpause(id) do
      :ok ->
        log_inspect_status(docker, id, "after unpause")
        :ok

      {:error, _} = e ->
        engine_line("unpause -> #{inspect(e)}")
        e
    end
  end

  defp log_inspect_status(docker, id, label) do
    case docker.container_inspect(id) do
      {:ok, %{"State" => %{"Status" => s}}} ->
        engine_line("inspect #{label}: Status=#{s}")

      {:ok, _} ->
        engine_line("inspect #{label}: (no State.Status)")

      {:error, _} = e ->
        engine_line("inspect #{label} -> #{inspect(e)}")
    end
  end

  defp cleanup(docker, cfg, id) do
    t = cfg[:stop_timeout_sec]

    engine_line("POST /containers/#{short_id(id)}/stop?t=#{t}")
    _ = docker.container_stop(id, timeout_sec: t)

    engine_line("DELETE /containers/#{short_id(id)}?force=1")
    _ = docker.container_remove(id, force: true)
    :ok
  end

  defp short_id(id) when is_binary(id) do
    id |> String.trim_leading("sha256:") |> String.slice(0, 12)
  end

  defp narrate(text), do: line(:narrator, text)
  defp engine_line(text), do: line(:engine, text)

  defp line(kind, text) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second)

    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      VmLifecycle.topic(),
      {:vm_manager_preflight, {:line, kind, ts, text}}
    )
  end

  defp broadcast_preflight_session(:clear) do
    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      VmLifecycle.topic(),
      {:vm_manager_preflight, {:session, :clear}}
    )
  end

  defp broadcast_preflight_session(%{} = data) do
    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      VmLifecycle.topic(),
      {:vm_manager_preflight, {:session, data}}
    )
  end
end
