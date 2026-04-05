defmodule Companion.InferencePreflight do
  @moduledoc """
  HTTP preflight for OpenAI-compatible inference servers (e.g. Ollama `/v1`).

  Performs `GET {base}/models` with optional `Authorization: Bearer …`.
  Does not run model weights or store secrets beyond the caller's use.
  """

  @finch Companion.Finch
  @receive_timeout 15_000

  @doc """
  Probes `{openai_base}/models` where `openai_base` is normalized to include `/v1`.

  Returns `{:ok, %{status: 200, model_count: n, model_ids: [...], sample_ids: [binary()]}}` or `{:error, iodata}`.
  """
  @spec check_models(String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def check_models(openai_base_url, opts \\ []) when is_binary(openai_base_url) do
    api_key = Keyword.get(opts, :api_key, "")

    with {:ok, base} <- normalize_openai_base_url(openai_base_url),
         {:ok, url} <- build_models_url(base) do
      headers = [{"accept", "application/json"}]

      headers =
        if is_binary(api_key) and String.trim(api_key) != "" do
          [{"authorization", "Bearer " <> String.trim(api_key)} | headers]
        else
          headers
        end

      req = Finch.build(:get, url, headers)

      case Finch.request(req, @finch, receive_timeout: @receive_timeout) do
        {:ok, %Finch.Response{status: 200, body: body}} ->
          parse_models_body(body)

        {:ok, %Finch.Response{status: status, body: body}} ->
          {:error, format_http_error(status, body)}

        {:error, reason} ->
          {:error, "request failed: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Normalizes a user-entered host or OpenAI base string to end with `/v1`.
  Shared with `Companion.InferenceChat`.
  """
  @spec normalize_openai_base_url(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def normalize_openai_base_url(url) when is_binary(url) do
    u = url |> String.trim() |> String.trim_trailing("/")

    cond do
      u == "" ->
        {:error, "base URL is empty"}

      String.ends_with?(u, "/v1") ->
        {:ok, u}

      true ->
        {:ok, u <> "/v1"}
    end
  end

  defp build_models_url(base) do
    {:ok, base <> "/models"}
  end

  defp parse_models_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, %{"data" => data}} when is_list(data) ->
        ids =
          data
          |> Enum.map(fn
            %{"id" => id} when is_binary(id) -> id
            _ -> nil
          end)
          |> Enum.reject(&is_nil/1)

        {:ok,
         %{
           status: 200,
           model_count: length(ids),
           model_ids: ids,
           sample_ids: Enum.take(ids, 8)
         }}

      {:ok, other} ->
        {:error, "unexpected JSON shape: #{inspect(Map.keys(other || %{}))}"}

      {:error, _} ->
        {:error, "response is not valid JSON"}
    end
  end

  defp format_http_error(status, body) when is_binary(body) do
    snippet =
      body
      |> String.slice(0, 200)
      |> String.replace(~r/\s+/, " ")

    "HTTP #{status}" <> if(snippet == "", do: "", else: ": #{snippet}")
  end
end
