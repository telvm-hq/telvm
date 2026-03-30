defmodule Companion.PreflightTest do
  use ExUnit.Case, async: true

  alias Companion.Preflight

  describe "vm_node_filters/0" do
    test "includes telvm.sandbox label and running status" do
      f = Preflight.vm_node_filters()
      assert %{"label" => ["telvm.sandbox=true"], "status" => ["running"]} == f
      encoded = URI.encode_query(%{"filters" => Jason.encode!(f)})
      assert encoded =~ "telvm.sandbox"
      assert encoded =~ "running"
    end
  end

  describe "compute_rollup/1" do
    test "blocked when any gating check fails" do
      checks = [
        %{kind: :gating, status: :pass, id: :a},
        %{kind: :gating, status: :fail, id: :b}
      ]

      assert Preflight.compute_rollup(checks) == :blocked
    end

    test "ready when all gating checks pass" do
      checks = [
        %{kind: :gating, status: :pass, id: :a},
        %{kind: :gating, status: :pass, id: :b}
      ]

      assert Preflight.compute_rollup(checks) == :ready
    end

    test "degraded when gating has warn or skip" do
      checks = [
        %{kind: :gating, status: :pass, id: :a},
        %{kind: :gating, status: :warn, id: :b}
      ]

      assert Preflight.compute_rollup(checks) == :degraded

      checks2 = [
        %{kind: :gating, status: :pass, id: :a},
        %{kind: :gating, status: :skip, id: :b}
      ]

      assert Preflight.compute_rollup(checks2) == :degraded
    end

    test "ignores informational rows for rollup" do
      checks = [
        %{kind: :gating, status: :pass, id: :a},
        %{kind: :info, status: :info, id: :b}
      ]

      assert Preflight.compute_rollup(checks) == :ready
    end
  end
end
