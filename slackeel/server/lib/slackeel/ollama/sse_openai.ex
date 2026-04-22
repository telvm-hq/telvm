defmodule Slackeel.Ollama.SseOpenAI do
  @moduledoc false

  @doc """
  Incrementally parses OpenAI-style `text/event-stream` chunks; returns `{text_deltas, rest_buffer}`.
  """
  def drain(buffer) when is_binary(buffer), do: drain(buffer, [])

  defp drain(buf, acc_texts) do
    case String.split(buf, "\n\n", parts: 2) do
      [event, rest] ->
        texts = extract_texts_from_event(event)
        drain(rest, acc_texts ++ texts)

      _ ->
        {Enum.reject(acc_texts, &(&1 == "")), buf}
    end
  end

  defp extract_texts_from_event(event) do
    event
    |> String.split("\n", trim: true)
    |> Enum.flat_map(fn line ->
      case String.trim_leading(line) do
        "data: [DONE]" ->
          []

        "data: " <> json ->
          case Jason.decode(json) do
            {:ok, %{"choices" => [%{"delta" => %{"content" => t}} | _]}} when is_binary(t) ->
              [t]

            {:ok, %{"choices" => [%{"delta" => delta} | _]}} ->
              t = Map.get(delta, "content") || Map.get(delta, :content)
              if is_binary(t), do: [t], else: []

            _ ->
              []
          end

        _ ->
          []
      end
    end)
  end
end
