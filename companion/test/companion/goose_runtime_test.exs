defmodule Companion.GooseRuntimeTest do
  use ExUnit.Case, async: true

  alias Companion.GooseRuntime

  test "find_container/0 returns not_found when Docker list is empty (mock)" do
    assert {:error, :not_found} = GooseRuntime.find_container()
  end

  test "run_text/2 returns assistant text from mock exec" do
    assert {:ok, text} = GooseRuntime.run_text("container-id", "hello")
    assert text =~ "Hello"
  end
end
