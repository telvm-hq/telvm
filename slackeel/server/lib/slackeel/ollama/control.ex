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
            if verbose?,
              do: IO.puts(:stderr, "[ollama] pull error field: #{inspect(err, limit: :infinity)}")

            {:error, {:api, err}}

          other ->
            if verbose?,
              do:
                IO.puts(
                  :stderr,
                  "[ollama] pull unexpected 200 body: #{inspect(other, limit: :infinity)}"
                )

            {:error, {:pull_response, other}}
        end

      {:ok, %{status: s, body: body}} ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] pull HTTP #{s} #{inspect(body, limit: :infinity)}")

        {:error, {:http, s, body}}

      {:error, reason} = err ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] pull transport #{inspect(reason, limit: :infinity)}")

        err
    end
  end

  @doc """
  `POST /api/pull` with `stream: true`. Invokes `on_progress.(pct_or_nil, status)` for each decoded JSON line
  (`pct_or_nil` is 0..100 when `completed`/`total` are present, else `nil` for indeterminate ticks).
  Returns `{:ok, :pulled}` or `{:error, term}`.
  """
  def pull_stream(model, on_progress, opts \\ [])
      when is_binary(model) and is_function(on_progress, 2) do
    verbose? = Keyword.get(opts, :verbose, false)
    timeout = Keyword.get(opts, :receive_timeout) || Config.ollama_pull_timeout_ms()
    base = Config.ollama_base_url()
    url = base <> "/api/pull"
    body = %{"model" => model, "stream" => true}
    buf_key = {:slackeel_pull_stream_buf, make_ref()}

    if verbose? do
      IO.puts(:stderr, "[ollama] POST #{url} (pull stream) model=#{inspect(model)}")
    end

    Process.put(buf_key, "")

    result =
      Req.post(url,
        json: body,
        finch: Slackeel.Finch,
        receive_timeout: timeout,
        retry: :transient,
        max_retries: 0,
        into: fn {:data, data}, {req, resp} ->
          buf = Process.get(buf_key, "") <> data
          {lines, rest} = pull_stream_collect_lines(buf, [])
          Process.put(buf_key, rest)

          for line <- lines, line != "" do
            case Jason.decode(line) do
              {:ok, m} when is_map(m) -> pull_stream_notify(m, on_progress)
              _ -> :ok
            end
          end

          {:cont, {req, resp}}
        end
      )

    Process.delete(buf_key)

    case result do
      {:ok, %{status: 200}} ->
        {:ok, :pulled}

      {:ok, %{status: s, body: body}} ->
        {:error, {:http, s, body}}

      {:error, _} = err ->
        err
    end
  end

  defp pull_stream_collect_lines("", acc), do: {Enum.reverse(acc), ""}

  defp pull_stream_collect_lines(buf, acc) do
    case String.split(buf, "\n", parts: 2) do
      [line, rest] -> pull_stream_collect_lines(rest, [line | acc])
      [tail] -> {Enum.reverse(acc), tail}
    end
  end

  defp pull_stream_notify(%{"error" => err}, on_progress) do
    on_progress.(nil, "error: #{inspect(err, limit: 80)}")
  end

  defp pull_stream_notify(%{"status" => "success"}, on_progress) do
    on_progress.(100, "success")
  end

  defp pull_stream_notify(
         %{"completed" => c, "total" => t} = m,
         on_progress
       )
       when is_number(c) and is_number(t) and t > 0 do
    c = if is_float(c), do: round(c), else: c
    t = if is_float(t), do: round(t), else: t
    pct = min(100, max(0, round(c * 100 / t)))
    on_progress.(pct, Map.get(m, "status") || "pulling")
  end

  defp pull_stream_notify(%{"status" => st}, on_progress) when is_binary(st) do
    on_progress.(nil, st)
  end

  defp pull_stream_notify(_, _on_progress), do: :ok

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
        if verbose?,
          do:
            IO.puts(
              :stderr,
              "[ollama] unload 404 (model not loaded): #{inspect(body, limit: 120)}"
            )

        {:ok, :nothing_to_unload}

      {:ok, %{status: s, body: body}} ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] unload HTTP #{s} #{inspect(body, limit: 200)}")

        {:error, {:http, s, body}}

      {:error, reason} = err ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] unload transport #{inspect(reason, limit: :infinity)}")

        err
    end
  end

  @doc """
  `GET /api/ps` — running models on the Ollama host (empty list if API missing or error).
  """
  def ps(opts \\ []) do
    verbose? = Keyword.get(opts, :verbose, false)
    timeout = Keyword.get(opts, :receive_timeout, 15_000)
    base = Config.ollama_base_url()
    url = base <> "/api/ps"

    case Req.get(url,
           finch: Slackeel.Finch,
           receive_timeout: timeout,
           retry: :transient,
           max_retries: 0
         ) do
      {:ok, %{status: 200, body: %{"models" => models}}} when is_list(models) ->
        {:ok, models}

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] ps unexpected 200: #{inspect(body, limit: 120)}")

        {:ok, []}

      {:ok, %{status: s, body: body}} ->
        if verbose?, do: IO.puts(:stderr, "[ollama] ps HTTP #{s} #{inspect(body, limit: 120)}")
        {:error, {:http, s, body}}

      {:error, reason} = err ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] ps transport #{inspect(reason, limit: :infinity)}")

        err
    end
  end

  @doc """
  `POST /api/generate` with a tiny completion and a long `keep_alive` so weights stay resident.
  """
  def warm(model, opts \\ []) when is_binary(model) do
    verbose? = Keyword.get(opts, :verbose, false)
    timeout = Keyword.get(opts, :receive_timeout) || Config.ollama_chat_timeout_ms()
    keep_alive = Keyword.get(opts, :keep_alive) || Config.hot_models_keep_alive()
    base = Config.ollama_base_url()
    url = base <> "/api/generate"

    body = %{
      "model" => model,
      "prompt" => "",
      "stream" => false,
      "keep_alive" => keep_alive,
      "options" => %{"num_predict" => 1}
    }

    if verbose? do
      IO.puts(
        :stderr,
        "[ollama] POST #{url} (warm num_predict=1 keep_alive=#{inspect(keep_alive)})"
      )
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
          %{"error" => err} ->
            {:error, {:api, err}}

          _ ->
            {:ok, :warm}
        end

      {:ok, %{status: s, body: body}} ->
        if verbose?, do: IO.puts(:stderr, "[ollama] warm HTTP #{s} #{inspect(body, limit: 200)}")
        {:error, {:http, s, body}}

      {:error, reason} = err ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] warm transport #{inspect(reason, limit: :infinity)}")

        err
    end
  end
end
