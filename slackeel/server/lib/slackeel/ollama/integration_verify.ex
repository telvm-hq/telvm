defmodule Slackeel.Ollama.IntegrationVerify do
  @moduledoc false

  alias Slackeel.Ollama.{Chat, Config}

  @doc """
  Sends the configured probe prompt as a single user message and returns assistant text and probe metadata
  (duration, optional token counts, derived `tokens_per_sec`).

  Options: `:verbose` — forwarded to `Slackeel.Ollama.Chat.completion/3`.
  """
  def probe(ollama_model, opts \\ []) when is_binary(ollama_model) and is_list(opts) do
    prompt = Keyword.get(opts, :prompt) || Config.integration_verify_prompt()
    verbose? = Keyword.get(opts, :verbose, false)

    case Chat.completion(ollama_model, [%{"role" => "user", "content" => prompt}], verbose: verbose?) do
      {:ok, text, meta} -> {:ok, String.trim(text), meta}
      {:error, _} = e -> e
    end
  end
end
