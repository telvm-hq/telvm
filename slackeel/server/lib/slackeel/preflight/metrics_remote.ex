defmodule Slackeel.Preflight.MetricsRemote do
  @moduledoc false

  @doc """
  Fetches JSON from `Application.get_env(:slackeel, :preflight_metrics_url)` (see `config/config.exs`).
  Optional `:preflight_metrics_token` sets `Authorization: Bearer`.

  Accepted shapes include:
  - `{\"free_bytes\": <int>}`
  - `{\"disk_free_bytes\": <int>}`
  - `{\"metrics\": {\"free_bytes\": <int>}}`
  """
  def fetch do
    url = Application.get_env(:slackeel, :preflight_metrics_url)

    if is_binary(url) and url != "" do
      timeout = Application.get_env(:slackeel, :preflight_metrics_timeout_ms, 5_000)

      opts = [
        finch: Slackeel.Finch,
        receive_timeout: timeout,
        retry: :transient,
        max_retries: 0
      ]

      opts =
        case auth_headers() do
          [] -> opts
          headers -> Keyword.put(opts, :headers, headers)
        end

      case Req.get(url, opts) do
        {:ok, %{status: 200, body: body}} when is_map(body) ->
          parse_body(body)

        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          case Jason.decode(body) do
            {:ok, map} when is_map(map) -> parse_body(map)
            _ -> {:error, {:bad_json, :not_object}}
          end

        {:ok, %{status: s, body: b}} ->
          {:error, {:http, s, b}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :no_url}
    end
  end

  defp auth_headers do
    case Application.get_env(:slackeel, :preflight_metrics_token) do
      t when is_binary(t) and t != "" ->
        [{"authorization", "Bearer " <> t}]

      _ ->
        []
    end
  end

  defp parse_body(body) do
    free =
      cond do
        v = body["free_bytes"] -> coerce_non_neg_int(v)
        v = body["disk_free_bytes"] -> coerce_non_neg_int(v)
        is_map(body["metrics"]) ->
          coerce_non_neg_int(body["metrics"]["free_bytes"])

        true ->
          nil
      end

    if is_integer(free) and free >= 0 do
      origin =
        case body do
          %{"source" => "telvm-network-agent"} -> :telvm_network_agent
          _ -> :http_metrics
        end

      {:ok,
       %{
         origin: origin,
         effective_free_bytes: free,
         raw: body
       }}
    else
      {:error, :bad_json_shape}
    end
  end

  defp coerce_non_neg_int(v) when is_integer(v), do: v

  defp coerce_non_neg_int(v) when is_float(v) do
    trunc(v)
  end

  defp coerce_non_neg_int(v) when is_binary(v) do
    case Integer.parse(String.trim(v)) do
      {i, _} when i >= 0 -> i
      _ -> nil
    end
  end

  defp coerce_non_neg_int(_), do: nil
end
