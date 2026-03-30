defmodule Companion.PreflightServer do
  @moduledoc false

  use GenServer

  @default_interval :timer.seconds(5)

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    interval = Keyword.get(opts, :interval, @default_interval)
    send(self(), :tick)
    {:ok, %{interval: interval}}
  end

  @impl true
  def handle_info(:tick, %{interval: interval} = state) do
    report = Companion.Preflight.run()

    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      Companion.Preflight.topic(),
      {:report, report}
    )

    Process.send_after(self(), :tick, interval)
    {:noreply, state}
  end
end
