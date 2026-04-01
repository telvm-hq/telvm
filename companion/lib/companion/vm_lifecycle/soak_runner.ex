defmodule Companion.VmLifecycle.SoakRunner do
  @moduledoc false

  alias Companion.VmLifecycle

  @topic "lifecycle:soak_monitor"
  @default_soak_ms 60_000
  @default_bind_timeout_ms 10_000
  @probe_interval_ms 400

  def topic, do: @topic

  def soak_run(overrides \\ []) when is_list(overrides) do
    {result, meta} =
      try do
        docker = Companion.Docker.impl()
        cfg = VmLifecycle.manager_preflight_config(overrides)
        soak_ms = Keyword.get(overrides, :soak_duration_ms, @default_soak_ms)
        bind_ms = Keyword.get(overrides, :soak_bind_timeout_ms, @default_bind_timeout_ms)

        narrate("Soak monitor: creating container with image=#{cfg[:image]}")

        name = "telvm-vm-mgr-" <> Integer.to_string(:erlang.unique_integer([:positive]))
        attrs = VmLifecycle.lab_container_create_attrs(cfg, name)
        engine_line("POST /containers/create name=#{name} image=#{cfg[:image]}")

        case docker.container_create(attrs) do
          {:ok, cid} ->
            engine_line("created id=#{short_id(cid)}")
            broadcast({:soak_monitor, {:session, %{container_id: cid, phase: :bind}}})
            run_soak(docker, cfg, cid, soak_ms, bind_ms)

          {:error, reason} ->
            engine_line("container_create failed: #{inspect(reason)}")
            {{:error, reason}, nil}
        end
      rescue
        e -> {{:error, Exception.message(e)}, nil}
      end

    broadcast({:soak_monitor, {:session, :clear}})

    case meta do
      nil ->
        broadcast({:soak_monitor, {:done, result, %{}}})

      m when is_map(m) ->
        broadcast({:soak_monitor, {:done, result, m}})
    end

    case result do
      :ok -> :ok
      {:error, r} -> {:error, r}
    end
  end

  def soak_run_async(overrides \\ []) do
    Task.start(fn -> soak_run(overrides) end)
  end

  defp run_soak(docker, cfg, cid, soak_ms, bind_ms) do
    engine_line("POST /containers/#{short_id(cid)}/start")

    case docker.container_start(cid, []) do
      :ok ->
        engine_line("start -> ok")

        case wait_running(docker, cid, cfg) do
          :ok ->
            port = cfg[:exposed_port]
            path = cfg[:http_probe_path]
            host = cfg[:dns_alias]
            url = "http://#{host}:#{port}#{path}"
            bind_deadline = System.monotonic_time(:millisecond) + bind_ms

            narrate(
              "Bind wait: probing #{url} (up to #{div(bind_ms, 1000)}s) until first HTTP 200…"
            )

            case wait_first_200(url, bind_deadline) do
              :ok ->
                broadcast({:soak_monitor, {:session, %{container_id: cid, phase: :stability}}})
                narrate("Stability window: probing #{url} for #{div(soak_ms, 1000)}s")

                case stability_loop(url, soak_ms) do
                  {:ok, ok_count, fail_count} ->
                    meta = base_meta(cid, cfg, soak_ms, ok_count, fail_count)

                    if fail_count == 0 do
                      total = ok_count + fail_count

                      narrate(
                        "Stability complete: #{ok_count}/#{total} probes returned 200 (stability window only)."
                      )

                      {:ok, Map.put(meta, :soak, :ok)}
                    else
                      narrate(
                        "Stability complete: #{ok_count}/#{ok_count + fail_count} probes returned 200 (#{fail_count} failed)"
                      )

                      {{:error, "#{fail_count}/#{ok_count + fail_count} stability probes failed"},
                       Map.put(meta, :soak, :error)}
                    end

                  {:error, reason} ->
                    meta = base_meta(cid, cfg, soak_ms, 0, 0)
                    {{:error, reason}, Map.put(meta, :soak, :error)}
                end

              {:error, :bind_timeout} ->
                engine_line("bind wait: no HTTP 200 before deadline")
                meta = base_meta(cid, cfg, soak_ms, 0, 0)
                {{:error, :bind_timeout}, Map.put(meta, :soak, :error)}
            end

          {:error, _} = e ->
            {e, base_meta(cid, cfg, soak_ms, 0, 0)}
        end

      {:error, _} = e ->
        engine_line("start -> #{inspect(e)}")
        {e, nil}
    end
  end

  defp base_meta(cid, cfg, soak_ms, ok, fail) do
    %{
      container_id: cid,
      image: cfg[:image],
      exposed_port: cfg[:exposed_port],
      soak_ms: soak_ms,
      stability_probes: %{ok: ok, fail: fail}
    }
  end

  defp wait_running(docker, cid, cfg) do
    deadline = System.monotonic_time(:millisecond) + cfg[:wait_running_timeout_ms]
    wait_running_loop(docker, cid, deadline)
  end

  defp wait_running_loop(docker, cid, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      engine_line("inspect: timeout waiting for running")
      {:error, :wait_running_timeout}
    else
      case docker.container_inspect(cid) do
        {:ok, %{"State" => %{"Status" => "running"}}} ->
          engine_line("inspect State.Status=running")
          :ok

        {:ok, %{"State" => %{"Status" => s}}} ->
          engine_line("inspect State.Status=#{s}, retry…")
          Process.sleep(300)
          wait_running_loop(docker, cid, deadline)

        {:error, _} = e ->
          engine_line("inspect -> #{inspect(e)}")
          e
      end
    end
  end

  defp wait_first_200(url, bind_deadline) do
    if System.monotonic_time(:millisecond) >= bind_deadline do
      {:error, :bind_timeout}
    else
      case http_probe(url) do
        {:ok, %{status: 200, latency_ms: ms}} ->
          engine_line("GET #{url} -> 200 (#{ms}ms)")
          narrate("Probe service ready (first 200).")
          :ok

        {:ok, %{status: status, latency_ms: ms}} ->
          engine_line("GET #{url} -> #{status} (#{ms}ms)")
          Process.sleep(@probe_interval_ms)
          wait_first_200(url, bind_deadline)

        {:error, reason} ->
          engine_line("GET #{url} -> error #{inspect(reason)}")
          Process.sleep(@probe_interval_ms)
          wait_first_200(url, bind_deadline)
      end
    end
  end

  defp stability_loop(url, soak_ms) do
    deadline = System.monotonic_time(:millisecond) + soak_ms
    stability_loop(url, deadline, 0, 0)
  end

  defp stability_loop(url, deadline, ok_count, fail_count) do
    if System.monotonic_time(:millisecond) >= deadline do
      {:ok, ok_count, fail_count}
    else
      case http_probe(url) do
        {:ok, %{status: 200, latency_ms: ms}} ->
          engine_line("GET #{url} -> 200 (#{ms}ms)")
          Process.sleep(@probe_interval_ms)
          stability_loop(url, deadline, ok_count + 1, fail_count)

        {:ok, %{status: status, latency_ms: ms}} ->
          engine_line("GET #{url} -> #{status} (#{ms}ms)")
          Process.sleep(@probe_interval_ms)
          stability_loop(url, deadline, ok_count, fail_count + 1)

        {:error, reason} ->
          engine_line("GET #{url} -> error #{inspect(reason)}")
          Process.sleep(@probe_interval_ms)
          stability_loop(url, deadline, ok_count, fail_count + 1)
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
      f when is_function(f, 1) -> f.(url)
      _ -> Companion.VmLifecycle.HttpProbe.get(url)
    end
  end

  defp short_id(id) when is_binary(id) do
    id |> String.trim_leading("sha256:") |> String.slice(0, 12)
  end

  defp narrate(text), do: line(:narrator, text)
  defp engine_line(text), do: line(:engine, text)

  defp line(kind, text) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second)
    broadcast({:soak_monitor, {:line, kind, ts, text}})
  end

  defp broadcast(msg) do
    Phoenix.PubSub.broadcast(Companion.PubSub, @topic, msg)
  end
end
