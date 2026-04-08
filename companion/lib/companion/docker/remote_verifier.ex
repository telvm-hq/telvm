defmodule Companion.Docker.RemoteVerifier do
  @moduledoc """
  One-shot smoke test for the Zig agent Docker proxy endpoints.

  Boots, waits for `NetworkAgentPoller` to discover reachable Zig agents,
  then exercises every `Docker.Remote` function against each one. Results
  are logged as PASS / FAIL / SKIP and stored in state for `iex` inspection
  via `RemoteVerifier.results/0`.
  """

  use GenServer
  require Logger

  @initial_delay :timer.seconds(15)
  @token "test123"

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

        Logger.info("RemoteVerifier: starting verification for #{hostname} (#{base_url})")
        checks = verify_agent(base_url)

        pass = Enum.count(checks, fn {_, s, _} -> s == :pass end)
        fail = Enum.count(checks, fn {_, s, _} -> s == :fail end)
        skip = Enum.count(checks, fn {_, s, _} -> s == :skip end)

        Logger.info(
          "RemoteVerifier: #{hostname} done — #{pass} PASS, #{fail} FAIL, #{skip} SKIP"
        )

        %{host: hostname, ip: ip, checks: checks}
      end)

    {:noreply, %{state | results: results, ran_at: DateTime.utc_now()}}
  end

  defp discover_hosts do
    case Companion.NetworkAgentPoller.snapshot() do
      %{last_snapshot: %{hosts: hosts}} when is_list(hosts) ->
        Enum.filter(hosts, fn h -> h["zig_agent_status"] == "ok" end)

      _ ->
        Logger.warning("RemoteVerifier: no hosts discovered — NetworkAgentPoller not ready?")
        []
    end
  end

  defp verify_agent(base_url) do
    alias Companion.Docker.Remote

    checks = []

    # 1. version (GET)
    checks = checks ++ [check("version", fn -> Remote.version(base_url, @token) end)]

    # 2. container_list (GET)
    {list_result, containers} =
      case Remote.container_list(base_url, @token, all: true) do
        {:ok, list} -> {{:ok, list}, list}
        err -> {err, []}
      end

    checks = checks ++ [to_check("container_list", list_result)]

    first_container = List.first(containers)
    first_id = if first_container, do: first_container["Id"]

    running =
      Enum.find(containers, fn c ->
        (c["State"] || "") |> String.downcase() |> String.starts_with?("running")
      end)

    running_id = if running, do: running["Id"]

    # 3. container_inspect (GET)
    checks =
      checks ++
        if first_id do
          [check("container_inspect", fn -> Remote.container_inspect(base_url, @token, first_id) end)]
        else
          [skip("container_inspect", "no containers")]
        end

    # 4. container_logs (GET, binary demux)
    checks =
      checks ++
        if first_id do
          [check("container_logs", fn -> Remote.container_logs(base_url, @token, first_id) end)]
        else
          [skip("container_logs", "no containers")]
        end

    # 5. container_stats (GET)
    checks =
      checks ++
        if running_id do
          [check("container_stats", fn -> Remote.container_stats(base_url, @token, running_id) end)]
        else
          [skip("container_stats", "no running container")]
        end

    # 6. pause / unpause (POST)
    checks =
      checks ++
        if running_id do
          pause_result = check("container_pause", fn -> Remote.container_pause(base_url, @token, running_id) end)

          unpause_result =
            case pause_result do
              {_, :pass, _} ->
                check("container_unpause", fn -> Remote.container_unpause(base_url, @token, running_id) end)

              _ ->
                skip("container_unpause", "pause failed")
            end

          [pause_result, unpause_result]
        else
          [skip("container_pause", "no running container"), skip("container_unpause", "no running container")]
        end

    # 7. exec (POST body — runs `echo hello`)
    checks =
      checks ++
        if running_id do
          [
            check("container_exec", fn ->
              case Remote.container_exec(base_url, @token, running_id, ["echo", "hello"]) do
                {:ok, output} ->
                  if String.contains?(output, "hello"),
                    do: {:ok, output},
                    else: {:error, {:unexpected_output, output}}

                err ->
                  err
              end
            end)
          ]
        else
          [skip("container_exec", "no running container")]
        end

    # 8. stop / start — SKIP to avoid disruption
    checks =
      checks ++
        [
          skip("container_stop", "skipped to avoid disruption"),
          skip("container_start", "skipped to avoid disruption")
        ]

    # 9. remove — SKIP
    checks = checks ++ [skip("container_remove", "skipped to avoid disruption")]

    checks
  end

  defp check(name, fun) do
    try do
      case fun.() do
        :ok ->
          log_result(name, :pass, "ok")
          {name, :pass, "ok"}

        {:ok, _data} ->
          log_result(name, :pass, "ok")
          {name, :pass, "ok"}

        {:error, reason} ->
          log_result(name, :fail, inspect(reason))
          {name, :fail, inspect(reason)}
      end
    rescue
      e ->
        log_result(name, :fail, Exception.message(e))
        {name, :fail, Exception.message(e)}
    end
  end

  defp to_check(name, result) do
    case result do
      {:ok, _} ->
        log_result(name, :pass, "ok")
        {name, :pass, "ok"}

      {:error, reason} ->
        log_result(name, :fail, inspect(reason))
        {name, :fail, inspect(reason)}
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

    Logger.info("RemoteVerifier:   [#{tag}] #{name} — #{detail}")
  end
end
