defmodule Companion.Docker.RemoteVerifier do
  @moduledoc """
  One-shot smoke test for the Zig agent Docker proxy endpoints.

  Boots, waits for `NetworkAgentPoller` to discover reachable Zig agents,
  then exercises every `Docker.Remote` function against each one. Results
  are logged as PASS / FAIL / SKIP and stored in state for `iex` inspection
  via `RemoteVerifier.results/0`.

  Designed to be resilient against:
  - Single-threaded Zig agent blocking on slow Docker calls (per-call timeouts)
  - Missing containers (graceful SKIPs)
  - Exec 3-step flow failures (dependency chaining)
  - State restoration (stop→start leaves container running)
  """

  use GenServer
  require Logger

  @initial_delay :timer.seconds(15)
  @token "test123"
  @call_timeout 15_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def results do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      _pid -> GenServer.call(__MODULE__, :results)
    end
  end

  @impl true
  def init(_opts) do
    Process.send_after(self(), :run, @initial_delay)
    {:ok, %{results: nil, ran_at: nil}}
  end

  @impl true
  def handle_call(:results, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:run, state) do
    hosts = discover_hosts()

    results =
      Enum.map(hosts, fn host ->
        ip = host["ip"]
        hostname = get_in(host, ["zig_agent_health", "hostname"]) || ip
        base_url = "http://#{ip}:9100"

        Logger.info("RemoteVerifier: ── starting verification for #{hostname} (#{base_url}) ──")
        checks = verify_agent(base_url)

        pass = Enum.count(checks, fn {_, s, _} -> s == :pass end)
        fail = Enum.count(checks, fn {_, s, _} -> s == :fail end)
        skip = Enum.count(checks, fn {_, s, _} -> s == :skip end)

        Logger.info(
          "RemoteVerifier: ── #{hostname} complete: #{pass} PASS, #{fail} FAIL, #{skip} SKIP ──"
        )

        %{host: hostname, ip: ip, checks: checks}
      end)

    {:noreply, %{state | results: results, ran_at: DateTime.utc_now()}}
  end

  # ---------------------------------------------------------------------------
  # Host discovery
  # ---------------------------------------------------------------------------

  defp discover_hosts do
    case Companion.NetworkAgentPoller.snapshot() do
      %{last_snapshot: %{hosts: hosts}} when is_list(hosts) ->
        Enum.filter(hosts, fn h -> h["zig_agent_status"] == "ok" end)

      _ ->
        Logger.warning("RemoteVerifier: no hosts discovered -- NetworkAgentPoller not ready?")
        []
    end
  end

  # ---------------------------------------------------------------------------
  # Full verification sequence
  # ---------------------------------------------------------------------------

  defp verify_agent(base_url) do
    alias Companion.Docker.Remote

    checks = []

    # ── 1. version (GET) ──
    checks = checks ++ [timed_check("version", fn -> Remote.version(base_url, @token) end)]

    # ── 2. container_list (GET) ──
    {list_result, containers} =
      timed_call(fn -> Remote.container_list(base_url, @token, all: true) end)

    checks = checks ++ [result_to_check("container_list", list_result)]

    first_container = List.first(containers || [])
    first_id = if first_container, do: first_container["Id"]

    running =
      Enum.find(containers || [], fn c ->
        state = c["State"] || ""
        is_binary(state) and String.downcase(state) == "running"
      end)

    running_id = if running, do: running["Id"]

    # ── 3. container_inspect (GET) ──
    checks =
      checks ++
        if first_id do
          [timed_check("container_inspect", fn -> Remote.container_inspect(base_url, @token, first_id) end)]
        else
          [skip("container_inspect", "no containers on host")]
        end

    # ── 4. container_logs (GET, binary demux) ──
    checks =
      checks ++
        if first_id do
          [timed_check("container_logs", fn -> Remote.container_logs(base_url, @token, first_id) end)]
        else
          [skip("container_logs", "no containers on host")]
        end

    # ── 5. container_stats (GET) ──
    checks =
      checks ++
        if running_id do
          [timed_check("container_stats", fn -> Remote.container_stats(base_url, @token, running_id) end)]
        else
          [skip("container_stats", "no running container")]
        end

    # ── 6. pause + unpause (POST) ──
    checks =
      checks ++
        if running_id do
          pause_result =
            timed_check("container_pause", fn ->
              Remote.container_pause(base_url, @token, running_id)
            end)

          unpause_result =
            if elem(pause_result, 1) == :pass do
              timed_check("container_unpause", fn ->
                Remote.container_unpause(base_url, @token, running_id)
              end)
            else
              skip("container_unpause", "skipped because pause failed")
            end

          [pause_result, unpause_result]
        else
          [
            skip("container_pause", "no running container"),
            skip("container_unpause", "no running container")
          ]
        end

    # ── 7. exec (POST body -- `echo hello`) ──
    checks =
      checks ++
        if running_id do
          [
            timed_check("container_exec", fn ->
              case Remote.container_exec(base_url, @token, running_id, ["echo", "hello"]) do
                {:ok, output} ->
                  if String.contains?(output, "hello"),
                    do: {:ok, "output contains 'hello'"},
                    else: {:error, {:unexpected_output, String.slice(output, 0, 200)}}

                err ->
                  err
              end
            end)
          ]
        else
          [skip("container_exec", "no running container")]
        end

    # ── 8. exec_with_exit (POST body -- validates exit_code) ──
    checks =
      checks ++
        if running_id do
          [
            timed_check("container_exec_with_exit", fn ->
              case Remote.container_exec_with_exit(base_url, @token, running_id, ["echo", "remote_verifier_ok"]) do
                {:ok, %{stdout: out, exit_code: 0}} ->
                  if String.contains?(out, "remote_verifier_ok"),
                    do: {:ok, "exit_code=0, output valid"},
                    else: {:error, {:unexpected_output, String.slice(out, 0, 200)}}

                {:ok, %{exit_code: code}} ->
                  {:error, {:nonzero_exit, code}}

                err ->
                  err
              end
            end)
          ]
        else
          [skip("container_exec_with_exit", "no running container")]
        end

    # ── 9. stop + start (POST, restore state) ──
    checks =
      checks ++
        if running_id do
          stop_result =
            timed_check("container_stop", fn ->
              Remote.container_stop(base_url, @token, running_id)
            end)

          start_result =
            if elem(stop_result, 1) == :pass do
              # Always attempt start to restore original state
              result =
                timed_check("container_start", fn ->
                  Remote.container_start(base_url, @token, running_id)
                end)

              if elem(result, 1) != :pass do
                Logger.warning(
                  "RemoteVerifier: WARNING -- container #{String.slice(running_id, 0, 12)} stopped but failed to restart!"
                )
              end

              result
            else
              skip("container_start", "skipped because stop failed")
            end

          [stop_result, start_result]
        else
          [
            skip("container_stop", "no running container"),
            skip("container_start", "no running container")
          ]
        end

    # ── 10. restart (POST) ──
    checks =
      checks ++
        if running_id do
          [
            timed_check("container_restart", fn ->
              Remote.container_restart(base_url, @token, running_id)
            end)
          ]
        else
          [skip("container_restart", "no running container")]
        end

    # ── 11. delete -- SKIP (no create route to make a disposable container) ──
    checks =
      checks ++
        [skip("container_remove", "no container_create route on Zig agent -- cannot safely test DELETE")]

    checks
  end

  # ---------------------------------------------------------------------------
  # Timeout-wrapped execution
  # ---------------------------------------------------------------------------

  defp timed_check(name, fun) do
    task = Task.async(fn -> safe_call(fun) end)

    case Task.yield(task, @call_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:pass, detail}} ->
        log_result(name, :pass, detail)
        {name, :pass, detail}

      {:ok, {:fail, detail}} ->
        log_result(name, :fail, detail)
        {name, :fail, detail}

      nil ->
        log_result(name, :fail, "timeout (#{@call_timeout}ms)")
        {name, :fail, "timeout (#{@call_timeout}ms)"}
    end
  end

  defp safe_call(fun) do
    try do
      case fun.() do
        :ok -> {:pass, "ok"}
        {:ok, data} when is_binary(data) -> {:pass, data}
        {:ok, _data} -> {:pass, "ok"}
        {:error, reason} -> {:fail, inspect(reason)}
      end
    rescue
      e -> {:fail, "exception: #{Exception.message(e)}"}
    catch
      kind, reason -> {:fail, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp timed_call(fun) do
    task = Task.async(fn -> safe_raw_call(fun) end)

    case Task.yield(task, @call_timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {{:error, :timeout}, []}
    end
  end

  defp safe_raw_call(fun) do
    try do
      case fun.() do
        {:ok, data} -> {{:ok, data}, data}
        err -> {err, []}
      end
    rescue
      _ -> {{:error, :exception}, []}
    catch
      _, _ -> {{:error, :caught}, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Result helpers
  # ---------------------------------------------------------------------------

  defp result_to_check(name, result) do
    case result do
      {:ok, _} ->
        log_result(name, :pass, "ok")
        {name, :pass, "ok"}

      {:error, reason} ->
        detail = inspect(reason)
        log_result(name, :fail, detail)
        {name, :fail, detail}
    end
  end

  defp skip(name, reason) do
    log_result(name, :skip, reason)
    {name, :skip, reason}
  end

  defp log_result(name, status, detail) do
    tag =
      case status do
        :pass -> "PASS"
        :fail -> "FAIL"
        :skip -> "SKIP"
      end

    Logger.info("RemoteVerifier:   [#{tag}] #{name} -- #{detail}")
  end
end
