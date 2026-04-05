defmodule Companion.GooseHealth.Snapshot do
  @moduledoc false

  @enforce_keys [:checked_at]
  defstruct checked_at: nil,
            container: nil,
            binary: :skipped,
            ollama: :skipped,
            agent_run: :skipped
end

defmodule Companion.GooseHealth do
  @moduledoc false

  use GenServer

  alias Companion.GooseHealth.Snapshot
  alias Companion.GooseRuntime

  @pubsub_topic "goose:health"

  @doc false
  def topic, do: @pubsub_topic

  @doc """
  Runs connectivity checks (container label, Goose binary, Ollama from inside the Goose container, optional `goose run`).
  """
  @spec verify(keyword()) :: %Snapshot{}
  def verify(opts \\ []) do
    sample_run? = Keyword.get(opts, :sample_run, true)
    checked_at = DateTime.utc_now() |> DateTime.truncate(:second)

    case GooseRuntime.find_container() do
      {:error, :not_found} ->
        %Snapshot{
          checked_at: checked_at,
          container: {:error, :not_found},
          binary: :skipped,
          ollama: :skipped,
          agent_run: :skipped
        }

      {:error, reason} ->
        %Snapshot{
          checked_at: checked_at,
          container: {:error, inspect(reason)},
          binary: :skipped,
          ollama: :skipped,
          agent_run: :skipped
        }

      {:ok, id, _status} ->
        docker = Companion.Docker.impl()
        binary = check_goose_binary(docker, id)
        ollama = check_ollama_reachable(docker, id)

        agent_run =
          cond do
            not sample_run? ->
              :skipped

            match?({:error, _}, binary) ->
              :skipped

            true ->
              case GooseRuntime.run_text(id, "hello") do
                {:ok, _} -> :ok
                {:error, msg} -> {:error, msg}
              end
          end

        %Snapshot{
          checked_at: checked_at,
          container: {:ok, id},
          binary: binary,
          ollama: ollama,
          agent_run: agent_run
        }
    end
  end

  defp check_goose_binary(docker, id) do
    case docker.container_exec_with_exit(id, [GooseRuntime.goose_bin(), "--version"], []) do
      {:ok, %{exit_code: 0}} ->
        :ok

      {:ok, %{stdout: out, exit_code: code}} ->
        hint = String.trim(to_string(out))

        {:error,
         "goose --version failed (exit #{code})" <> if(hint != "", do: ": " <> hint, else: "")}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  defp check_ollama_reachable(docker, id) do
    cmd = ["curl", "-sfS", "--max-time", "12", "http://ollama:11434/api/tags"]

    case docker.container_exec_with_exit(id, cmd, []) do
      {:ok, %{exit_code: 0}} ->
        :ok

      {:ok, %{stdout: out, exit_code: code}} ->
        hint = String.trim(to_string(out))
        err = "curl ollama:11434 failed (exit #{code})"

        {:error, if(hint == "", do: err, else: err <> " " <> hint)}

      {:error, reason} ->
        {:error, inspect(reason)}
    end
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def refresh do
    GenServer.cast(__MODULE__, :refresh)
  end

  @doc "Last snapshot from the most recent check (may be `nil` if disabled or not yet run)."
  def snapshot do
    GenServer.call(__MODULE__, :snapshot)
  end

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)
    interval_ms = Keyword.get(opts, :interval_ms, :timer.minutes(5))
    sample_run = Keyword.get(opts, :sample_run, true)

    state = %{
      enabled: enabled,
      interval_ms: interval_ms,
      sample_run: sample_run,
      last: nil
    }

    if enabled do
      send(self(), :tick)
    end

    {:ok, state}
  end

  @impl true
  def handle_info(:tick, state) do
    if state.enabled do
      snap = verify(sample_run: state.sample_run)
      broadcast(snap)
      Process.send_after(self(), :tick, state.interval_ms)
      {:noreply, %{state | last: snap}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast(:refresh, state) do
    snap = verify(sample_run: state.sample_run)
    broadcast(snap)
    {:noreply, %{state | last: snap}}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, state.last, state}
  end

  defp broadcast(%Snapshot{} = snap) do
    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      @pubsub_topic,
      {:goose_health, snap}
    )
  end
end
