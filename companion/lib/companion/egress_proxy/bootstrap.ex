defmodule Companion.EgressProxy.Bootstrap do
  @moduledoc false
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    workloads =
      Application.get_env(:companion, Companion.EgressProxy, [])
      |> Keyword.get(:workloads, [])

    for w <- workloads do
      spec = %{
        id: w.id,
        start: {Companion.EgressProxy.Listener, :start_link, [w]},
        restart: :permanent
      }

      {:ok, _} = DynamicSupervisor.start_child(Companion.EgressProxy.ListenerSup, spec)
    end

    {:ok, %{count: length(workloads)}}
  end
end
