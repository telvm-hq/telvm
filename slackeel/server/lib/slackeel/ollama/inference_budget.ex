defmodule Slackeel.Ollama.InferenceBudget do
  @moduledoc false

  alias Slackeel.Ollama.Config
  alias Slackeel.Preflight.ModelSizes

  def budget_bytes, do: Config.inference_memory_budget_bytes()

  def margin_bytes(ollama_tag) when is_binary(ollama_tag) do
    approx = ModelSizes.approx_pull_bytes(ollama_tag)
    v = Config.inference_memory_variance()
    ceil(approx * v)
  end

  def sum_margins(tags) when is_list(tags) do
    Enum.reduce(tags, 0, fn t, acc -> acc + margin_bytes(t) end)
  end
end
