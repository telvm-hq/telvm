defmodule Slackeel.Preflight do
  @moduledoc """
  Pre-flight snapshot: disk headroom from **`telvm-network-agent`** `GET /preflight/metrics` when configured,
  else local BEAM **`:disksup`**, plus manifest rows with per-model enablement for pulls.
  """

  alias Slackeel.Preflight.{DiskLocal, MetricsRemote, ModelSizes}

  @doc """
  Returns `{:ok, [ollama_tag, ...]}` from the configured manifest, or `{:error, reason}`.
  """
  def manifest_ollama_tags do
    manifest_path = Application.get_env(:slackeel, :manifest_path)

    with {:ok, body} <- File.read(manifest_path),
         {:ok, decoded} <- Jason.decode(body),
         models when is_list(models) <- decoded["models"] do
      {:ok,
       models
       |> Enum.map(fn row -> Map.get(row, "ollama") || Map.get(row, :ollama) end)
       |> Enum.filter(&is_binary/1)}
    else
      {:error, _} = e -> e
      _ -> {:error, :bad_manifest}
    end
  end

  @doc """
  Builds a full dashboard payload: metrics origin, effective free bytes, manifest rows.
  """
  def snapshot do
    variance = Application.get_env(:slackeel, :preflight_disk_variance, 1.15)

    {metrics, remote_err} =
      case MetricsRemote.fetch() do
        {:ok, m} ->
          {m, nil}

        {:error, :no_url} ->
          case DiskLocal.snapshot() do
            {:ok, m} -> {m, nil}
            {:error, local_reason} -> {nil, {:local_failed, local_reason}}
          end

        {:error, remote_reason} ->
          case DiskLocal.snapshot() do
            {:ok, m} ->
              {m, {:remote_failed, remote_reason}}

            {:error, local_reason} ->
              {nil, {:both_failed, remote: remote_reason, local: local_reason}}
          end
      end

    case metrics do
      nil ->
        {:error, {:metrics, remote_err}}

      m ->
        manifest_path = Application.get_env(:slackeel, :manifest_path)

        with {:ok, body} <- File.read(manifest_path),
             {:ok, decoded} <- Jason.decode(body),
             models when is_list(models) <- decoded["models"] do
          rows =
            Enum.map(models, fn row ->
              ollama = row["ollama"]
              approx = ModelSizes.approx_pull_bytes(ollama)
              margin = ceil(approx * variance)
              free = m.effective_free_bytes
              enabled = free >= margin

              %{
                id: row["id"],
                family: row["family"],
                ollama: ollama,
                required?: row["required"] == true,
                approx_pull_bytes: approx,
                margin_bytes: margin,
                enabled?: enabled
              }
            end)

          {:ok,
           %{
             origin: m.origin,
             effective_free_bytes: m.effective_free_bytes,
             disks: Map.get(m, :disks, []),
             remote_raw: Map.get(m, :raw),
             remote_error: remote_err,
             models: rows
           }}
        else
          {:error, _} = e -> e
          _ -> {:error, :bad_manifest}
        end
    end
  end
end
