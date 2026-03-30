defmodule Companion.VmLifecycle.RunnerTest do
  use ExUnit.Case, async: false

  alias Companion.VmLifecycle

  setup do
    flush_vm_manager_preflight_mailbox()
    Phoenix.PubSub.subscribe(Companion.PubSub, VmLifecycle.topic())
    :ok
  end

  test "run_vm_manager_preflight completes against Docker.Mock and stub HTTP probe" do
    assert :ok = Companion.VmLifecycle.Runner.run_vm_manager_preflight()
    assert_vm_manager_preflight_done()
  end

  test "run_vm_manager_preflight with overrides completes against Docker.Mock" do
    assert :ok =
             Companion.VmLifecycle.Runner.run_vm_manager_preflight(
               image: "ghcr.io/example/lab:main",
               use_image_default_cmd: true
             )

    assert_vm_manager_preflight_done()
  end

  defp flush_vm_manager_preflight_mailbox do
    receive do
      {:vm_manager_preflight, _} -> flush_vm_manager_preflight_mailbox()
    after
      0 -> :ok
    end
  end

  defp assert_vm_manager_preflight_done do
    receive do
      {:vm_manager_preflight, {:done, :ok}} -> :ok
      {:vm_manager_preflight, {:done, other}} -> flunk("expected :ok, got #{inspect(other)}")
      {:vm_manager_preflight, _} -> assert_vm_manager_preflight_done()
    after
      5000 -> flunk("VM manager pre-flight did not finish")
    end
  end
end
