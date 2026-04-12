defmodule Companion.EgressProxy.Listener do
  @moduledoc false
  use GenServer
  require Logger

  def start_link(workload) when is_map(workload) do
    GenServer.start_link(__MODULE__, workload, name: via(workload.id))
  end

  defp via(id), do: {:via, Registry, {Companion.EgressProxy.Registry, {:listener, id}}}

  def init(workload) do
    listen_opts = [
      :binary,
      active: false,
      packet: :raw,
      reuseaddr: true,
      backlog: 128,
      ip: {0, 0, 0, 0}
    ]

    case :gen_tcp.listen(workload.port, listen_opts) do
      {:ok, listen_sock} ->
        Logger.info("egress_proxy listener #{workload.id} on port #{workload.port}")
        send(self(), :accept)
        {:ok, %{listen: listen_sock, workload: workload}}

      {:error, reason} ->
        Logger.error("egress_proxy listener #{workload.id} listen failed: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  def handle_info(:accept, %{listen: ls, workload: w} = state) do
    case :gen_tcp.accept(ls) do
      {:ok, client} ->
        # Accepted sockets inherit listen opts (binary, active: false, packet: :raw).
        # Re-applying packet: :raw here can return {:error, :einval} on some OTP/Linux
        # stacks and crash the listener — client sees RST (e.g. curl exit 56).

        Task.Supervisor.start_child(
          Companion.EgressProxy.TaskSupervisor,
          fn -> Companion.EgressProxy.Connection.handle_client(client, w) end
        )

      {:error, :closed} ->
        {:stop, :normal, state}

      {:error, e} ->
        Logger.debug("egress_proxy accept error #{inspect(e)}")
    end

    send(self(), :accept)
    {:noreply, state}
  end
end
