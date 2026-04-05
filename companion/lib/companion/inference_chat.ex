defmodule Companion.InferenceChat do
  @moduledoc """
  Non-streaming OpenAI-compatible chat completions (`POST /v1/chat/completions`).

  Used for the Agent setup smoke chat; inference still runs in Ollama (or another server), not in BEAM.
  """

  alias Companion.InferencePreflight

  @finch Companion.Finch
  @default_receive_timeout 120_000

  @doc """
  Sends `messages` to `model` at the given OpenAI base URL (must include `/v1`).

  `messages` is a list of `%{"role" => "user" | "assistant" | "system", "content" => binary}`.
  """
  @spec chat_completion(String.t(), String.t(), String.t(), list(map()), keyword()) ::
          {:ok, String.t()} | {:error, String.t()}
  def chat_completion(openai_base_url, api_key, model, messages, opts \\ [])
      when is_binary(openai_base_url) and is_binary(model) and is_list(messages) do
    receive_timeout = Keyword.get(opts, :receive_timeout, @default_receive_timeout)

    with {:ok, base} <- InferencePreflight.normalize_openai_base_url(openai_base_url),
         {:ok, url} <- build_chat_url(base) do
      body =
        Jason.encode!(%{
          "model" => model,
          "messages" => messages,
          "stream" => false
        })

      headers = [
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ]

      headers =
        if is_binary(api_key) and String.trim(api_key) != "" do
          [{"authorization", "Bearer " <> String.trim(api_key)} | headers]
        else
          headers
        end

      req = Finch.build(:post, url, headers, body)

      case Finch.request(req, @finch, receive_timeout: receive_timeout) do
        {:ok, %Finch.Response{status: 200, body: resp_body}} ->
          parse_chat_completion_body(resp_body)

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, format_http_error(status, body)}

        {:error, reason} ->
          {:error, "request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc false
  @spec parse_chat_completion_body(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def parse_chat_completion_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"choices" => [%{"message" => %{"content" => content}} | _]}}
      when is_binary(content) ->
        {:ok, content}

      {:ok, %{"error" => %{"message" => msg}}} when is_binary(msg) ->
        {:error, msg}

      {:ok, other} ->
        {:error, "unexpected JSON shape: #{inspect(Map.keys(other || %{}))}"}

      {:error, _} ->
        {:error, "response is not valid JSON"}
    end
  end

  defp build_chat_url(base), do: {:ok, base <> "/chat/completions"}

  defp format_http_error(status, body) when is_binary(body) do
    snippet =
      body
      |> String.slice(0, 400)
      |> String.replace(~r/\s+/, " ")

    "HTTP #{status}" <> if(snippet == "", do: "", else: ": #{snippet}")
  end
end
