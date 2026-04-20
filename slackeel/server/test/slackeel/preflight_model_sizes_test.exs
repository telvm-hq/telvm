defmodule Slackeel.Preflight.ModelSizesTest do
  use ExUnit.Case, async: true

  alias Slackeel.Preflight.ModelSizes

  test "known catalog entries" do
    assert ModelSizes.approx_pull_bytes("qwen2.5:0.5b") == 400_000_000
    assert ModelSizes.approx_pull_bytes("mistral:7b") == 4_400_000_000
  end

  test "unknown tags use conservative default" do
    assert ModelSizes.approx_pull_bytes("unknown:tag") == 800_000_000
  end
end
