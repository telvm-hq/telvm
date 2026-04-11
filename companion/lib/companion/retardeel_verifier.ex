defmodule Companion.RetardeelVerifier do
  @moduledoc """
  TDD-style verifier for the retardeel Zig filesystem agent.

  Builds the retardeel binary via Docker, injects it into an existing lab
  container (telvm.sandbox=true), seeds a test workspace, starts the agent,
  exercises every endpoint, then cleans up. Results are broadcast over PubSub
  and stored in GenServer state for inspection.
  """

  use GenServer
  require Logger

  @topic "retardeel:verify"
  @token "retardeel-test"
  @agent_port 9200
  @http_timeout 8_000
  @call_timeout 15_000
  @docker_image "retardeel:latest"
  @build_context "/agents/retardeel"

  def topic, do: @topic

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def results do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :not_running}
      _pid -> GenServer.call(__MODULE__, :results)
    end
  end

  def verify do
    GenServer.cast(__MODULE__, :verify)
  end

  @impl true
  def init(_opts) do
    {:ok, %{status: :idle, results: nil, ran_at: nil}}
  end

  @impl true
  def handle_call(:results, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_cast(:verify, %{status: :running} = state) do
    {:noreply, state}
  end

  def handle_cast(:verify, state) do
    state = %{state | status: :running, results: nil}
    broadcast(%{status: :running, results: nil, ran_at: nil})

    parent = self()

    Task.start(fn ->
      result = run_verification()
      send(parent, {:verification_done, result})
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info({:verification_done, result}, state) do
    ran_at = DateTime.utc_now()
    state = %{state | status: :done, results: result, ran_at: ran_at}
    broadcast(%{status: :done, results: result, ran_at: ran_at})
    {:noreply, state}
  end

  # ---------------------------------------------------------------------------
  # Full verification pipeline
  # ---------------------------------------------------------------------------

  defp run_verification do
    Logger.info("RetardeelVerifier: starting verification pipeline")

    with {:ok, :built} <- build_binary(),
         {:ok, container_id} <- find_sandbox_container(),
         {:ok, :injected} <- inject_binary(container_id),
         {:ok, :seeded} <- seed_workspace(container_id),
         {:ok, :started} <- start_agent(container_id),
         {:ok, ip} <- get_container_ip(container_id) do
      base_url = "http://#{ip}:#{@agent_port}"
      Logger.info("RetardeelVerifier: agent reachable at #{base_url}")

      checks = wait_and_run_checks(base_url)

      cleanup(container_id)

      pass = Enum.count(checks, fn {_, s, _} -> s == :pass end)
      fail = Enum.count(checks, fn {_, s, _} -> s == :fail end)
      skip = Enum.count(checks, fn {_, s, _} -> s == :skip end)
      Logger.info("RetardeelVerifier: #{pass} PASS, #{fail} FAIL, #{skip} SKIP")

      checks
    else
      {:error, step, reason} ->
        Logger.error("RetardeelVerifier: pipeline failed at #{step}: #{inspect(reason)}")
        [{"pipeline_#{step}", :fail, inspect(reason)}]
    end
  end

  # ---------------------------------------------------------------------------
  # Step 1: Build the Docker image
  # ---------------------------------------------------------------------------

  defp build_binary do
    Logger.info("RetardeelVerifier: building #{@docker_image} from #{@build_context}")

    case System.cmd("docker", ["build", "-t", @docker_image, @build_context],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        Logger.info("RetardeelVerifier: image built successfully")
        {:ok, :built}

      {output, code} ->
        Logger.error("RetardeelVerifier: docker build failed (exit #{code})")
        {:error, :build, "docker build exit #{code}: #{String.slice(output, -500, 500)}"}
    end
  rescue
    e -> {:error, :build, Exception.message(e)}
  end

  # ---------------------------------------------------------------------------
  # Step 2: Find a running sandbox container
  # ---------------------------------------------------------------------------

  defp find_sandbox_container do
    docker = Companion.Docker.impl()

    case docker.container_list(filters: Companion.Preflight.vm_node_filters()) do
      {:ok, [first | _]} ->
        id = first["Id"]
        Logger.info("RetardeelVerifier: found sandbox container #{String.slice(id, 0, 12)}")
        {:ok, id}

      {:ok, []} ->
        {:error, :container, "no running container with label telvm.sandbox=true"}

      {:error, reason} ->
        {:error, :container, inspect(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Step 3: Extract binary from image, copy into target container
  # ---------------------------------------------------------------------------

  defp inject_binary(container_id) do
    tmp_name = "retardeel-extract-#{:rand.uniform(999_999)}"

    with {_, 0} <- System.cmd("docker", ["create", "--name", tmp_name, @docker_image],
                     stderr_to_stdout: true),
         {_, 0} <- System.cmd("docker", ["cp", "#{tmp_name}:/retardeel", "/tmp/retardeel"],
                     stderr_to_stdout: true),
         {_, 0} <- System.cmd("docker", ["cp", "/tmp/retardeel", "#{container_id}:/usr/local/bin/retardeel"],
                     stderr_to_stdout: true),
         {_, 0} <- System.cmd("docker", ["exec", container_id, "chmod", "+x", "/usr/local/bin/retardeel"],
                     stderr_to_stdout: true) do
      System.cmd("docker", ["rm", "-f", tmp_name], stderr_to_stdout: true)
      File.rm("/tmp/retardeel")
      Logger.info("RetardeelVerifier: binary injected into #{String.slice(container_id, 0, 12)}")
      {:ok, :injected}
    else
      {output, code} ->
        System.cmd("docker", ["rm", "-f", tmp_name], stderr_to_stdout: true)
        File.rm("/tmp/retardeel")
        {:error, :inject, "docker cp failed (exit #{code}): #{String.slice(output, -300, 300)}"}
    end
  rescue
    e -> {:error, :inject, Exception.message(e)}
  end

  # ---------------------------------------------------------------------------
  # Step 4: Create test workspace inside the container
  # ---------------------------------------------------------------------------

  defp seed_workspace(container_id) do
    docker = Companion.Docker.impl()

    cmds = [
      ["mkdir", "-p", "/tmp/retardeel-test/src"],
      ["sh", "-c", ~s(echo '{"name":"test"}' > /tmp/retardeel-test/package.json)],
      ["sh", "-c", ~s(echo 'defp deps, do: []' > /tmp/retardeel-test/mix.exs)],
      ["sh", "-c", ~s(echo 'defmodule Hello do\\nend' > /tmp/retardeel-test/src/hello.ex)]
    ]

    Enum.reduce_while(cmds, {:ok, :seeded}, fn cmd, _acc ->
      case docker.container_exec(container_id, cmd, []) do
        {:ok, _} -> {:cont, {:ok, :seeded}}
        {:error, reason} -> {:halt, {:error, :seed, "exec failed: #{inspect(reason)}"}}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Step 5: Start retardeel inside the container (backgrounded)
  # ---------------------------------------------------------------------------

  defp start_agent(container_id) do
    docker = Companion.Docker.impl()

    start_cmd = [
      "sh", "-c",
      "/usr/local/bin/retardeel --port #{@agent_port} --token #{@token} --root /tmp/retardeel-test " <>
        ">/tmp/retardeel.log 2>&1 & echo $! > /tmp/retardeel.pid && sleep 0"
    ]

    case docker.container_exec(container_id, start_cmd, []) do
      {:ok, _} ->
        Logger.info("RetardeelVerifier: agent started in container")
        {:ok, :started}

      {:error, reason} ->
        {:error, :start, inspect(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Step 5b: Get the container's IP on the Docker network
  # ---------------------------------------------------------------------------

  defp get_container_ip(container_id) do
    docker = Companion.Docker.impl()

    case docker.container_inspect(container_id) do
      {:ok, info} ->
        network = Application.get_env(:companion, :lab_docker_network, "telvm_default")
        ip = get_in(info, ["NetworkSettings", "Networks", network, "IPAddress"])

        if is_binary(ip) and ip != "" do
          {:ok, ip}
        else
          fallback = get_in(info, ["NetworkSettings", "IPAddress"])

          if is_binary(fallback) and fallback != "" do
            {:ok, fallback}
          else
            {:error, :ip, "could not determine container IP"}
          end
        end

      {:error, reason} ->
        {:error, :ip, inspect(reason)}
    end
  end

  # ---------------------------------------------------------------------------
  # Step 6: Wait for health then run all checks
  # ---------------------------------------------------------------------------

  defp wait_and_run_checks(base_url) do
    health_ok = wait_for_health(base_url, 10)

    if health_ok do
      run_checks(base_url)
    else
      [{"health_wait", :fail, "agent did not become healthy after retries"}]
    end
  end

  defp wait_for_health(_base_url, 0), do: false

  defp wait_for_health(base_url, retries) do
    case http_get(base_url <> "/health") do
      {:ok, 200, _body} -> true
      _ ->
        Process.sleep(500)
        wait_for_health(base_url, retries - 1)
    end
  end

  defp run_checks(base_url) do
    checks = []

    # 1. GET /health
    checks = checks ++ [timed_check("health", fn ->
      case http_get(base_url <> "/health") do
        {:ok, 200, body} ->
          if String.contains?(body, "retardeel"),
            do: {:ok, "ok"},
            else: {:error, "body missing 'retardeel'"}
        {:ok, status, _} -> {:error, "HTTP #{status}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 2. GET /v1/workspace
    checks = checks ++ [timed_check("workspace", fn ->
      case http_get(base_url <> "/v1/workspace") do
        {:ok, 200, body} ->
          if String.contains?(body, "mix.exs"),
            do: {:ok, "ok"},
            else: {:error, "body missing 'mix.exs'"}
        {:ok, status, _} -> {:error, "HTTP #{status}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 3. POST /v1/stat (existing file)
    checks = checks ++ [timed_check("stat_exists", fn ->
      case http_post(base_url <> "/v1/stat", %{path: "src/hello.ex"}) do
        {:ok, 200, body} ->
          if String.contains?(body, "\"exists\":true") or String.contains?(body, "\"exists\": true"),
            do: {:ok, "ok"},
            else: {:error, "expected exists:true, got #{String.slice(body, 0, 200)}"}
        {:ok, status, _} -> {:error, "HTTP #{status}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 4. POST /v1/stat (missing file)
    checks = checks ++ [timed_check("stat_missing", fn ->
      case http_post(base_url <> "/v1/stat", %{path: "does_not_exist.txt"}) do
        {:ok, 200, body} ->
          if String.contains?(body, "\"exists\":false") or String.contains?(body, "\"exists\": false"),
            do: {:ok, "ok"},
            else: {:error, "expected exists:false"}
        {:ok, status, _} -> {:error, "HTTP #{status}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 5. POST /v1/read
    checks = checks ++ [timed_check("read", fn ->
      case http_post(base_url <> "/v1/read", %{path: "src/hello.ex"}) do
        {:ok, 200, body} ->
          if String.contains?(body, "defmodule"),
            do: {:ok, "ok"},
            else: {:error, "body missing 'defmodule'"}
        {:ok, status, _} -> {:error, "HTTP #{status}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 6. POST /v1/write (create)
    checks = checks ++ [timed_check("write_create", fn ->
      case http_post(base_url <> "/v1/write", %{path: "created.txt", content_b64: "aGVsbG8=", mode: "create"}) do
        {:ok, 200, body} ->
          if String.contains?(body, "sha256"),
            do: {:ok, "ok"},
            else: {:error, "body missing 'sha256'"}
        {:ok, status, body} -> {:error, "HTTP #{status}: #{String.slice(body, 0, 200)}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 7. POST /v1/write (replace)
    checks = checks ++ [timed_check("write_replace", fn ->
      case http_post(base_url <> "/v1/write", %{path: "created.txt", content_b64: "d29ybGQ=", mode: "replace"}) do
        {:ok, 200, _body} -> {:ok, "ok"}
        {:ok, status, body} -> {:error, "HTTP #{status}: #{String.slice(body, 0, 200)}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 8. POST /v1/write (conflict: create when exists)
    checks = checks ++ [timed_check("write_conflict", fn ->
      case http_post(base_url <> "/v1/write", %{path: "created.txt", content_b64: "eA==", mode: "create"}) do
        {:ok, 409, _body} -> {:ok, "correctly rejected (409)"}
        {:ok, status, body} -> {:error, "expected 409, got HTTP #{status}: #{String.slice(body, 0, 200)}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 9. POST /v1/list
    checks = checks ++ [timed_check("list", fn ->
      case http_post(base_url <> "/v1/list", %{path: "src"}) do
        {:ok, 200, body} ->
          if String.contains?(body, "hello.ex"),
            do: {:ok, "ok"},
            else: {:error, "body missing 'hello.ex'"}
        {:ok, status, _} -> {:error, "HTTP #{status}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 10. POST /v1/read (jail escape attempt)
    checks = checks ++ [timed_check("jail_escape", fn ->
      case http_post(base_url <> "/v1/read", %{path: "../../etc/passwd"}) do
        {:ok, 403, _body} -> {:ok, "correctly blocked (403)"}
        {:ok, status, body} -> {:error, "expected 403, got HTTP #{status}: #{String.slice(body, 0, 200)}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    # 11. GET /health without auth (should be 401)
    checks = checks ++ [timed_check("no_auth", fn ->
      case http_get_no_auth(base_url <> "/health") do
        {:ok, 401, _body} -> {:ok, "correctly rejected (401)"}
        {:ok, status, _body} -> {:error, "expected 401, got HTTP #{status}"}
        {:error, reason} -> {:error, inspect(reason)}
      end
    end)]

    checks
  end

  # ---------------------------------------------------------------------------
  # Cleanup
  # ---------------------------------------------------------------------------

  defp cleanup(container_id) do
    docker = Companion.Docker.impl()

    kill_cmd = [
      "sh", "-c",
      "kill $(cat /tmp/retardeel.pid 2>/dev/null) 2>/dev/null; " <>
        "rm -rf /tmp/retardeel-test /tmp/retardeel.pid /tmp/retardeel.log /usr/local/bin/retardeel"
    ]

    case docker.container_exec(container_id, kill_cmd, []) do
      {:ok, _} -> Logger.info("RetardeelVerifier: cleanup complete")
      {:error, reason} -> Logger.warning("RetardeelVerifier: cleanup failed: #{inspect(reason)}")
    end
  end

  # ---------------------------------------------------------------------------
  # HTTP helpers (via Finch, not the Docker adapter)
  # ---------------------------------------------------------------------------

  defp http_get(url) do
    headers = [{"authorization", "Bearer #{@token}"}]
    req = Finch.build(:get, url, headers)

    case Finch.request(req, Companion.Finch, receive_timeout: @http_timeout) do
      {:ok, %Finch.Response{status: status, body: body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp http_get_no_auth(url) do
    req = Finch.build(:get, url, [])

    case Finch.request(req, Companion.Finch, receive_timeout: @http_timeout) do
      {:ok, %Finch.Response{status: status, body: body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end

  defp http_post(url, body_map) do
    headers = [
      {"authorization", "Bearer #{@token}"},
      {"content-type", "application/json"}
    ]

    body = Jason.encode!(body_map)
    req = Finch.build(:post, url, headers, body)

    case Finch.request(req, Companion.Finch, receive_timeout: @http_timeout) do
      {:ok, %Finch.Response{status: status, body: body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Timeout-wrapped check execution (same pattern as RemoteVerifier)
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
        {:ok, detail} -> {:pass, detail}
        {:error, reason} -> {:fail, inspect(reason)}
      end
    rescue
      e -> {:fail, "exception: #{Exception.message(e)}"}
    catch
      kind, reason -> {:fail, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp log_result(name, status, detail) do
    tag = case status do
      :pass -> "PASS"
      :fail -> "FAIL"
      :skip -> "SKIP"
    end

    Logger.info("RetardeelVerifier:   [#{tag}] #{name} -- #{detail}")
  end

  defp broadcast(payload) do
    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      @topic,
      {:retardeel_verify, payload}
    )
  end
end
