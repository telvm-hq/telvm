defmodule Slackeel.Ollama.Control do
  @moduledoc false

  # Native Ollama HTTP endpoints (not OpenAI-compatible `/v1/...`).
  # See https://github.com/ollama/ollama/blob/main/docs/api.md

  alias Slackeel.Ollama.Config

  @doc """
  `POST /api/pull` with `stream: false`. Ensures weights exist locally (idempotent if already pulled).
  """
  def pull(model, opts \\ []) when is_binary(model) do
    verbose? = Keyword.get(opts, :verbose, false)
    timeout = Keyword.get(opts, :receive_timeout) || Config.ollama_pull_timeout_ms()
    base = Config.ollama_base_url()
    url = base <> "/api/pull"
    body = %{"model" => model, "stream" => false}

    if verbose? do
      IO.puts(:stderr, "[ollama] POST #{url} (pull, stream=false)")
      IO.puts(:stderr, "[ollama] receive_timeout_ms=#{timeout} model=#{inspect(model)}")
    end

    case Req.post(url,
           json: body,
           finch: Slackeel.Finch,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 0
         ) do
      {:ok, %{status: 200, body: body}} when is_map(body) ->
        case body do
          %{"status" => "success"} ->
            {:ok, :pulled}

          %{"error" => err} ->
            if verbose?, do: IO.puts(:stderr, "[ollama] pull error field: #{inspect(err, limit: :infinity)}")
            {:error, {:api, err}}

          other ->
            if verbose?, do: IO.puts(:stderr, "[ollama] pull unexpected 200 body: #{inspect(other, limit: :infinity)}")
            {:error, {:pull_response, other}}
        end

      {:ok, %{status: s, body: body}} ->
        if verbose?, do: IO.puts(:stderr, "[ollama] pull HTTP #{s} #{inspect(body, limit: :infinity)}")
        {:error, {:http, s, body}}

      {:error, reason} = err ->
        if verbose?, do: IO.puts(:stderr, "[ollama] pull transport #{inspect(reason, limit: :infinity)}")
        err
    end
  end

  @doc """
  `POST /api/chat` with empty `messages`, `keep_alive: 0`, `stream: false` — unloads the model from VRAM.
  """
  def unload(model, opts \\ []) when is_binary(model) do
    verbose? = Keyword.get(opts, :verbose, false)
    timeout = Keyword.get(opts, :receive_timeout) || Config.ollama_chat_timeout_ms()
    base = Config.ollama_base_url()
    url = base <> "/api/chat"

    body = %{
      "model" => model,
      "messages" => [],
      "keep_alive" => 0,
      "stream" => false
    }

    if verbose? do
      IO.puts(:stderr, "[ollama] POST #{url} (unload keep_alive=0)")
    end

    case Req.post(url,
           json: body,
           finch: Slackeel.Finch,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 0
         ) do
      {:ok, %{status: 200}} ->
        {:ok, :unloaded}

      {:ok, %{status: 404, body: body}} ->
        if verbose?, do: IO.puts(:stderr, "[ollama] unload 404 (model not loaded): #{inspect(body, limit: 120)}")
        {:ok, :nothing_to_unload}

      {:ok, %{status: s, body: body}} ->
        if verbose?, do: IO.puts(:stderr, "[ollama] unload HTTP #{s} #{inspect(body, limit: 200)}")
        {:error, {:http, s, body}}

      {:error, reason} = err ->
        if verbose?, do: IO.puts(:stderr, "[ollama] unload transport #{inspect(reason, limit: :infinity)}")
        err
    end
  end
end
