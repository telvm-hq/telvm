defmodule Companion.VmLifecycle.Runner do
  @moduledoc false

  use GenServer

  @name __MODULE__
  @dynamic_supervisor Companion.VmLifecycle.RunnerDynamicSupervisor

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @doc """
  Runs the VM manager pre-flight script. Ensures this GenServer is running under
  `Companion.VmLifecycle.RunnerDynamicSupervisor` so dev hot-reload (which does not re-run
  `Application.start/2`) can still obtain a runner after the first click.

  Returns `{:error, :runner_supervisor_not_started}` if the DynamicSupervisor is missing
  (restart the BEAM / companion container).
  """
  def run_vm_manager_preflight(overrides \\ []) when is_list(overrides) do
    with :ok <- ensure_started() do
      GenServer.call(@name, {:run_vm_manager_preflight, overrides}, :infinity)
    end
  end

  defp ensure_started do
    cond do
      is_pid(Process.whereis(@name)) ->
        :ok

      !is_pid(Process.whereis(@dynamic_supervisor)) ->
        {:error, :runner_supervisor_not_started}

      true ->
        case DynamicSupervisor.start_child(@dynamic_supervisor, {__MODULE__, []}) do
          {:ok, _} -> :ok
          {:ok, _, _} -> :ok
          {:error, {:already_started, _}} -> :ok
          {:error, {:already_registered, _}} -> :ok
          {:error, reason} -> {:error, {:runner_start_failed, reason}}
        end
    end
  end

  @impl true
  def init(_opts), do: {:ok, %{busy: false}}

  @impl true
  def handle_call({:run_vm_manager_preflight, overrides}, _from, %{busy: true})
      when is_list(overrides) do
    {:reply, {:error, :busy}, %{busy: true}}
  end

  def handle_call({:run_vm_manager_preflight, overrides}, _from, %{busy: false})
      when is_list(overrides) do
    parent = self()

    _ =
      Task.start(fn ->
        result =
          try do
            Companion.VmLifecycle.Logic.run(overrides)
          rescue
            e -> {:error, Exception.message(e)}
          end

        send(parent, {:vm_manager_preflight_task_done, result})
      end)

    {:reply, :ok, %{busy: true}}
  end

  @impl true
  def handle_info({:vm_manager_preflight_task_done, _result}, _state) do
    {:noreply, %{busy: false}}
  end

  def handle_info(_, state), do: {:noreply, state}
end
