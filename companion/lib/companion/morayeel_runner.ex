defmodule Companion.MorayeelRunner do
  @moduledoc """
  Runs the **morayeel** Playwright image via Docker: build (if needed), `docker run`
  on the lab Docker network, write artifacts to a shared volume, broadcast progress on PubSub.

  Concurrency: only one run at a time (`:running` ignores duplicate `:run` casts).
  """

  use GenServer
  require Logger

  @topic "morayeel:run"

  def topic, do: @topic

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Enqueue a headless browser lab run (no-op if already running)."
  def run, do: GenServer.cast(__MODULE__, :run)

  @doc "Last completed or in-flight snapshot for LiveView mount."
  def snapshot do
    case Process.whereis(__MODULE__) do
      nil -> default_snapshot()
      pid -> GenServer.call(pid, :snapshot, 5_000)
    end
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       status: :idle,
       run_id: nil,
       docker_log: "",
       exit_code: nil,
       error: nil,
       summary: nil,
       ran_at: nil,
       last_run_id: nil
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state_to_public(state), state}
  end

  @impl true
  def handle_cast(:run, %{status: :running} = state) do
    broadcast(%{event: :rejected, message: "Morayeel run already in progress"})
    {:noreply, state}
  end

  def handle_cast(:run, state) do
    if skip_docker?() do
      broadcast(%{
        event: :rejected,
        message:
          "Morayeel Docker runs are disabled in Mix :test (see docs/morayeel-verification.md for a compose smoke)."
      })

      {:noreply, state}
    else
      run_id = random_run_id()
      parent = self()

      Task.start(fn ->
        result = run_pipeline(run_id)
        send(parent, {:morayeel_pipeline_done, result})
      end)

      state =
        %{
          state
          | status: :running,
            run_id: run_id,
            docker_log: "",
            exit_code: nil,
            error: nil,
            summary: nil
        }

      broadcast(%{event: :started, run_id: run_id, status: :running})
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:morayeel_pipeline_done, {:ok, data}}, state) do
    ran_at = DateTime.utc_now()

    state = %{
      state
      | status: data.status,
          run_id: data.run_id,
          docker_log: data.docker_log,
          exit_code: data.exit_code,
          error: data[:error],
          summary: data.summary,
          ran_at: ran_at,
          last_run_id: data.run_id
    }

    broadcast(Map.put(state_to_public(state), :event, :finished))
    {:noreply, state}
  end

  def handle_info({:morayeel_pipeline_done, {:error, step, reason}}, state)
      when is_atom(step) do
    ran_at = DateTime.utc_now()
    rid = state.run_id

    state = %{
      state
      | status: :failed,
          docker_log: "",
          exit_code: nil,
          error: "#{step}: #{reason}",
          summary: nil,
          ran_at: ran_at,
          last_run_id: rid || state.last_run_id
    }

    broadcast(Map.put(state_to_public(state), :event, :finished))
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp run_pipeline(run_id) do
    cfg = Application.get_env(:companion, __MODULE__, [])
    artifacts_dir = Keyword.get(cfg, :artifacts_dir, "/morayeel-runs")
    lab_url = Keyword.get(cfg, :lab_url, "http://morayeel_lab:8080/")
    net = Keyword.get(cfg, :docker_network, "telvm_default")
    http_proxy = Keyword.get(cfg, :http_proxy, "http://companion:4003")
    image = Keyword.get(cfg, :image, "morayeel:latest")
    dockerfile = Keyword.get(cfg, :dockerfile_path, "/agents/morayeel/Dockerfile")
    ctx = Keyword.get(cfg, :build_context, "/agents/morayeel")

    run_dir = Path.join(artifacts_dir, run_id)
    File.mkdir_p!(run_dir)

    Logger.info("MorayeelRunner: run_id=#{run_id} artifacts=#{run_dir}")

    case docker_build(image, dockerfile, ctx) do
      {:error, :build, msg} ->
        mark_run_failed(run_dir, run_id, msg)

        {:ok,
         %{
           status: :failed,
           run_id: run_id,
           docker_log: tail_text(msg, 8000),
           exit_code: nil,
           error: msg,
           summary: nil
         }}

      {:ok, build_log} ->
        case docker_run(image, net, run_id, lab_url, http_proxy, http_proxy) do
          {:ok, run_log, code} ->
            log = tail_text(build_log, 8000) <> "\n--- docker run ---\n" <> tail_text(run_log, 12_000)

            summary =
              Path.join(run_dir, "storageState.json")
              |> summarize_storage_state_with_retry()

            status = if code == 0, do: :passed, else: :failed

            {:ok,
             %{
               status: status,
               run_id: run_id,
               docker_log: log,
               exit_code: code,
               error: if(code == 0, do: nil, else: "playwright exit #{code}"),
               summary: summary
             }}
        end
    end
  rescue
    e ->
      {:error, :exception, Exception.message(e)}
  end

  defp mark_run_failed(run_dir, run_id, msg) do
    File.write!(
      Path.join(run_dir, "run.json"),
      Jason.encode!(%{"status" => "failed", "error" => msg, "run_id" => run_id})
    )
  end

  defp skip_docker? do
    Application.get_env(:companion, __MODULE__, []) |> Keyword.get(:skip_docker, false)
  end

  defp docker_build(image, dockerfile, context) do
    args = ["build", "-t", image, "-f", dockerfile, context]

    case System.cmd("docker", args, stderr_to_stdout: true) do
      {out, 0} ->
        {:ok, tail_text(out, 8000)}

      {out, code} ->
        msg = "docker build exit #{code}: #{tail_text(out, 2000)}"
        {:error, :build, msg}
    end
  end

  defp docker_run(image, network, run_id, lab_url, http_proxy, https_proxy) do
    # morayeel_lab must bypass HTTP_PROXY: Chromium often does not persist Set-Cookie into
    # storageState for same-origin pages fetched via an absolute-URL forwarding proxy (companion
    # egress GET). Direct Docker DNS to the lab keeps session artifacts truthful; :4003 remains
    # available for outbound traffic that does not bypass NO_PROXY.
    no_proxy = "companion,db,ollama,localhost,127.0.0.1,morayeel_lab"

    args =
      [
        "run",
        "--rm",
        "--network",
        network,
        "-v",
        "morayeel_runs:/artifacts",
        "-e",
        "TARGET_URL=#{lab_url}",
        "-e",
        "OUT_DIR=/artifacts/#{run_id}",
        "-e",
        "HTTP_PROXY=#{http_proxy}",
        "-e",
        "HTTPS_PROXY=#{https_proxy}",
        "-e",
        "NO_PROXY=#{no_proxy}",
        image
      ]

    case System.cmd("docker", args, stderr_to_stdout: true) do
      {out, code} ->
        {:ok, tail_text(out, 12_000), code}
    end
  end

  defp summarize_storage_state_with_retry(path, attempt \\ 1)

  defp summarize_storage_state_with_retry(path, attempt) do
    summary = Companion.Morayeel.StorageState.summarize_from_path(path)

    cond do
      summary[:cookie_count] > 0 ->
        summary

      attempt >= 15 ->
        summary

      storage_state_pending?(path, summary) ->
        Process.sleep(100)
        summarize_storage_state_with_retry(path, attempt + 1)

      true ->
        summary
    end
  end

  defp storage_state_pending?(path, summary) do
    cond do
      summary[:note] == "missing_file" -> true
      summary[:note] == "invalid_json" -> false
      true -> file_has_empty_cookie_jar?(path)
    end
  end

  defp file_has_empty_cookie_jar?(path) do
    case File.read(path) do
      {:ok, body} ->
        case Jason.decode(body) do
          {:ok, %{"cookies" => c}} when is_list(c) -> c == []
          {:ok, _} -> true
          {:error, _} -> false
        end

      {:error, _} ->
        true
    end
  end

  defp tail_text(str, max_bytes) when is_binary(str) and is_integer(max_bytes) do
    n = byte_size(str)
    if n <= max_bytes, do: str, else: binary_part(str, n - max_bytes, max_bytes)
  end

  defp random_run_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp broadcast(payload) do
    Phoenix.PubSub.broadcast(Companion.PubSub, @topic, {:morayeel_run, payload})
  end

  defp state_to_public(state) do
    %{
      status: state.status,
      run_id: state.run_id,
      docker_log: state.docker_log,
      exit_code: state.exit_code,
      error: state.error,
      summary: state.summary,
      ran_at: state.ran_at,
      last_run_id: state.last_run_id || state.run_id
    }
  end

  defp default_snapshot do
    %{
      status: :idle,
      run_id: nil,
      docker_log: "",
      exit_code: nil,
      error: nil,
      summary: nil,
      ran_at: nil,
      last_run_id: nil
    }
  end
end
