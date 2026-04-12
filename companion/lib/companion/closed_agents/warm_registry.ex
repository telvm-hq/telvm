defmodule Companion.ClosedAgentWarmRegistry do
  @moduledoc false
  use GenServer

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def register_verified(container_id) when is_binary(container_id) do
    GenServer.cast(__MODULE__, {:add, container_id})
  end

  @doc "Full container IDs that passed Machines → Basic soak for vendor CLI agents (in-memory; cleared on companion restart)."
  def verified_ids do
    GenServer.call(__MODULE__, :list)
  end

  def revoke(container_id) when is_binary(container_id) do
    GenServer.cast(__MODULE__, {:remove, container_id})
  end

  def member?(container_id) when is_binary(container_id) do
    container_id in verified_ids()
  end

  @impl true
  def init(:ok), do: {:ok, MapSet.new()}

  @impl true
  def handle_call(:list, _from, set), do: {:reply, MapSet.to_list(set), set}

  @impl true
  def handle_cast({:add, id}, set), do: {:noreply, MapSet.put(set, id)}

  @impl true
  def handle_cast({:remove, id}, set), do: {:noreply, MapSet.delete(set, id)}
end
