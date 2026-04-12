defmodule Companion.EgressProxy.History do
  @moduledoc false
  use GenServer

  @max_entries 24

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def record_deny(workload_id, host, reason \\ :not_on_allowlist) do
    GenServer.cast(__MODULE__, {:deny, workload_id, host, reason, DateTime.utc_now()})
  end

  def recent_deny_entries do
    GenServer.call(__MODULE__, :recent)
  end

  @impl true
  def init(_opts) do
    {:ok, %{entries: []}}
  end

  @impl true
  def handle_cast({:deny, workload_id, host, reason, at}, state) do
    entry = %{workload_id: workload_id, host: host, reason: reason, at: at}
    entries = Enum.take([entry | state.entries], @max_entries)
    {:noreply, %{state | entries: entries}}
  end

  @impl true
  def handle_call(:recent, _from, state) do
    {:reply, state.entries, state}
  end
end
