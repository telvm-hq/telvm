defmodule Slackeel.Preflight.ModelSizes do
  @moduledoc false

  # Approximate pull sizes (bytes); align with docs/MODEL_CATALOG.md — variance handled upstream.

  @sizes %{
    "qwen2.5:0.5b" => 400_000_000,
    "qwen2.5:1.5b" => 1_000_000_000,
    "llama3.2:1b" => 1_300_000_000,
    "llama3.2:3b" => 2_000_000_000,
    "gemma2:2b" => 1_600_000_000,
    "phi3:mini" => 2_200_000_000,
    "phi3:3.8b" => 2_300_000_000,
    "ministral-3:3b" => 3_000_000_000,
    "mistral:7b" => 4_400_000_000,
    "tinyllama" => 600_000_000
  }

  def approx_pull_bytes(ollama_name) when is_binary(ollama_name) do
    Map.get(@sizes, ollama_name, 800_000_000)
  end
end
