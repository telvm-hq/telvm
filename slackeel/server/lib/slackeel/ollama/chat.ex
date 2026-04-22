defmodule Slackeel.Ollama.Chat do
  @moduledoc false

  alias Slackeel.Ollama.Config

  @doc """
  POST OpenAI-compatible `POST /v1/chat/completions` to Ollama.
  Returns `{:ok, message_content, meta}` or `{:error, term}`.

  `meta` includes wall-clock `duration_ms`, optional `usage` token counts from the response,
  and `tokens_per_sec` when derivable (Ollama `eval_count`/`eval_duration` preferred, else
  `usage.completion_tokens` / round-trip time).

  Options:
  - `:verbose` — log request URL, timeouts, and response details to stderr (for CLI troubleshooting).
  """
  def completion(model, messages, opts \\ []) when is_binary(model) and is_list(messages) do
    verbose? = Keyword.get(opts, :verbose, false)
    base = Config.ollama_base_url()
    timeout = Config.ollama_chat_timeout_ms()
    url = base <> "/v1/chat/completions"

    body = %{
      "model" => model,
      "messages" => messages,
      "stream" => false
    }

    if verbose? do
      IO.puts(:stderr, "[ollama] POST #{url}")
      IO.puts(:stderr, "[ollama] receive_timeout_ms=#{timeout} model=#{inspect(model)}")

      prompt_preview =
        messages
        |> List.first()
        |> case do
          %{"content" => c} when is_binary(c) -> String.slice(c, 0, 80)
          _ -> ""
        end

      IO.puts(:stderr, "[ollama] user_message_preview=#{inspect(prompt_preview)}")
    end

    {duration_us, resp} =
      :timer.tc(fn ->
        Req.post(url,
          json: body,
          finch: Slackeel.Finch,
          receive_timeout: timeout,
          retry: :transient,
          max_retries: 0
        )
      end)

    duration_ms = duration_us / 1000

    case resp do
      {:ok,
       %{
         status: 200,
         body: %{"choices" => [%{"message" => %{"content" => text}} | _]} = resp_body
       }}
      when is_binary(text) ->
        if verbose? do
          prev = text |> String.replace("\n", " ") |> String.slice(0, 240)
          IO.puts(:stderr, "[ollama] HTTP 200 assistant_preview=#{inspect(prev)}")
        end

        {:ok, text, build_meta(resp_body, duration_ms, verbose?)}

      {:ok, %{status: 200, body: %{"choices" => [%{"message" => m} | _]} = resp_body}} ->
        c = Map.get(m, "content") || Map.get(m, :content)

        if is_binary(c) do
          if verbose? do
            prev = c |> String.replace("\n", " ") |> String.slice(0, 240)
            IO.puts(:stderr, "[ollama] HTTP 200 assistant_preview=#{inspect(prev)}")
          end

          {:ok, c, build_meta(resp_body, duration_ms, verbose?)}
        else
          {:error, {:bad_shape, m}}
        end

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        err = body["error"]

        if verbose?,
          do:
            IO.puts(
              :stderr,
              "[ollama] HTTP 200 but error field: #{inspect(err, limit: :infinity)}"
            )

        {:error, {:api, err || body}}

      {:ok, %{status: s, body: body}} ->
        if verbose? do
          IO.puts(:stderr, "[ollama] HTTP #{s} body=#{inspect(body, limit: :infinity)}")

          if s == 404 do
            IO.puts(
              :stderr,
              "[ollama] hint: model not loaded locally — run: ollama pull #{model}"
            )
          end
        end

        {:error, {:http, s, body}}

      {:error, reason} = err ->
        if verbose?,
          do: IO.puts(:stderr, "[ollama] transport error #{inspect(reason, limit: :infinity)}")

        err
    end
  end

  defp build_meta(resp_body, duration_ms, verbose?) when is_map(resp_body) do
    u = Map.get(resp_body, "usage") || %{}

    pt = pos_int(Map.get(u, "prompt_tokens"))
    ct = pos_int(Map.get(u, "completion_tokens"))
    tt = pos_int(Map.get(u, "total_tokens"))

    eval_count = pos_int(Map.get(resp_body, "eval_count"))
    eval_ns = pos_int(Map.get(resp_body, "eval_duration"))

    tokens_per_sec =
      cond do
        eval_count && eval_ns && eval_ns > 0 ->
          eval_count / (eval_ns / 1_000_000_000)

        ct && duration_ms > 0 ->
          ct / (duration_ms / 1000)

        true ->
          nil
      end

    tps =
      case tokens_per_sec do
        n when is_float(n) -> Float.round(n, 1)
        n when is_number(n) -> round(n * 10) / 10
        _ -> nil
      end

    source =
      cond do
        eval_count && eval_ns && eval_ns > 0 -> :eval
        ct && duration_ms > 0 -> :usage_wall_clock
        true -> :none
      end

    meta = %{
      duration_ms: Float.round(duration_ms * 1.0, 1),
      prompt_tokens: pt,
      completion_tokens: ct,
      total_tokens: tt,
      eval_count: eval_count,
      eval_duration_ns: eval_ns,
      tokens_per_sec: tps,
      throughput_source: source
    }

    if verbose? and tps do
      IO.puts(:stderr, "[ollama] probe meta: #{inspect(meta, limit: :infinity)}")
    end

    meta
  end

  defp pos_int(n) when is_integer(n) and n >= 0, do: n
  defp pos_int(n) when is_float(n) and n >= 0, do: round(n)

  defp pos_int(n) when is_binary(n) do
    case Integer.parse(n) do
      {i, _} when i >= 0 -> i
      _ -> nil
    end
  end

  defp pos_int(_), do: nil
end
