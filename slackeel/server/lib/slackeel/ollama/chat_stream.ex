defmodule Slackeel.Ollama.ChatStream do
  @moduledoc false

  alias Slackeel.Ollama.Config

  @doc """
  POST `/v1/chat/completions` with `stream: true`; forwards raw body chunks to `dest_pid` as
  `{:ollama_chat_sse, ref, binary}` then `{:ollama_chat_done, ref, :ok | {:error, term}}`.
  """
  def run(dest_pid, ref, model, messages)
      when is_pid(dest_pid) and is_reference(ref) and is_binary(model) and is_list(messages) do
    base = Config.ollama_base_url()
    timeout = Config.ollama_chat_timeout_ms()
    url = base <> "/v1/chat/completions"

    body = %{
      "model" => model,
      "messages" => messages,
      "stream" => true
    }

    result =
      Req.post(url,
        json: body,
        finch: Slackeel.Finch,
        receive_timeout: timeout,
        retry: :transient,
        max_retries: 0,
        into: fn {:data, data}, {req, resp} ->
          send(dest_pid, {:ollama_chat_sse, ref, data})
          {:cont, {req, resp}}
        end
      )

    done =
      case result do
        {:ok, %{status: 200}} ->
          :ok

        {:ok, %{status: s, body: body}} ->
          {:error, {:http, s, body}}

        {:error, reason} ->
          {:error, reason}
      end

    send(dest_pid, {:ollama_chat_done, ref, done})
  end
end
