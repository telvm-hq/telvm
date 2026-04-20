defmodule Slackeel.Ollama.Config do
  @moduledoc false

  @default_base "http://127.0.0.1:11434"

  @doc "Ollama HTTP API root (no trailing slash)."
  def ollama_base_url do
    case Application.get_env(:slackeel, :ollama_base_url) do
      nil -> @default_base
      "" -> @default_base
      url -> normalize_base(url)
    end
  end

  def ollama_chat_timeout_ms do
    Application.get_env(:slackeel, :ollama_chat_timeout_ms) || 120_000
  end

  def integration_verify_prompt do
    Application.get_env(:slackeel, :integration_verify_prompt) || "hello retard"
  end

  def integration_verify_max_parallel do
    Application.get_env(:slackeel, :integration_verify_max_parallel) || 3
  end

  @doc "Timeout for `POST /api/pull` (large downloads)."
  def ollama_pull_timeout_ms do
    Application.get_env(:slackeel, :ollama_pull_timeout_ms) || 7_200_000
  end

  defp normalize_base(url) when is_binary(url) do
    url = String.trim(url) |> String.trim_trailing("/")

    httpish? =
      String.starts_with?(url, "http://") or String.starts_with?(url, "https://")

    if url == "" or not httpish? do
      @default_base
    else
      url
    end
  end
end
