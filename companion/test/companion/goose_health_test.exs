defmodule Companion.GooseHealthTest do
  use ExUnit.Case, async: true

  alias Companion.GooseHealth
  alias Companion.GooseHealth.Snapshot

  test "verify/0 reports no container when Engine list is empty (mock)" do
    snap = GooseHealth.verify(sample_run: false)
    assert %Snapshot{} = snap
    assert {:error, :not_found} = snap.container
    assert snap.binary == :skipped
    assert snap.ollama == :skipped
    assert snap.agent_run == :skipped
  end

  test "goose_bin/0 matches Docker image install path" do
    assert Companion.GooseRuntime.goose_bin() == "/usr/local/bin/goose"
  end
end
