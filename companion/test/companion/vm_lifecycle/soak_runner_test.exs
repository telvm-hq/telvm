defmodule Companion.VmLifecycle.SoakRunnerTest do
  use ExUnit.Case, async: false

  alias Companion.VmLifecycle.SoakRunner

  setup do
    flush_soak_mailbox()
    Phoenix.PubSub.subscribe(Companion.PubSub, SoakRunner.topic())
    :ok
  end

  test "soak_run completes with mock adapter and broadcasts done" do
    result = SoakRunner.soak_run(soak_duration_ms: 1_200)
    assert result == :ok
    assert_soak_done()
  end

  test "soak_run_async spawns task that broadcasts done" do
    assert {:ok, _pid} = SoakRunner.soak_run_async(soak_duration_ms: 1_200)
    assert_soak_done()
  end

  defp flush_soak_mailbox do
    receive do
      {:soak_monitor, _} -> flush_soak_mailbox()
    after
      0 -> :ok
    end
  end

  defp assert_soak_done do
    receive do
      {:soak_monitor, {:done, :ok, %{container_id: _}}} ->
        :ok

      {:soak_monitor, {:done, :ok, _meta}} ->
        :ok

      {:soak_monitor, {:done, other, _}} ->
        flunk("expected :ok, got #{inspect(other)}")

      {:soak_monitor, {:done, other}} ->
        flunk("expected {:done, :ok, meta}, got #{inspect(other)}")

      {:soak_monitor, _} ->
        assert_soak_done()
    after
      10_000 -> flunk("Soak monitor did not finish within timeout")
    end
  end
end
