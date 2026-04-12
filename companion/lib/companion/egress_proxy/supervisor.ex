defmodule Companion.EgressProxy.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Registry, keys: :unique, name: Companion.EgressProxy.Registry},
      Companion.EgressProxy.History,
      {Finch,
       name: Companion.EgressProxy.Finch,
       pools: %{
         default: [size: 40, count: 1]
       }},
      {DynamicSupervisor,
       strategy: :one_for_one, name: Companion.EgressProxy.ListenerSup},
      {Task.Supervisor, name: Companion.EgressProxy.TaskSupervisor},
      Companion.EgressProxy.Bootstrap
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
