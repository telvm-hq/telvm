defmodule Slackeel.Preflight.DiskDuo do
  @moduledoc false
  @doc """
  Fetches two independent free-space readouts: HTTP host metrics (when configured)
  and this BEAM process view (`:disksup` or `df -Pk /` in a container). Used in the
  /chat footer to distinguish "local machine" from "this app / Docker view".
  """
  alias Slackeel.Preflight.{DiskLocal, MetricsRemote}

  @type label :: String.t()
  @type t :: %{host: {non_neg_integer(), label} | nil, app: {non_neg_integer(), label} | nil}

  @spec load() :: t()
  def load do
    host =
      case MetricsRemote.fetch() do
        {:ok, m} when is_map(m) ->
          {m.effective_free_bytes, host_label(Map.get(m, :origin, :http_metrics))}

        _ ->
          nil
      end

    app =
      case DiskLocal.snapshot() do
        {:ok, m} when is_map(m) ->
          {m.effective_free_bytes, "App / container (this process view)"}

        _ ->
          nil
      end

    %{host: host, app: app}
  end

  defp host_label(:telvm_network_agent), do: "Local machine (host · telvm-network-agent)"

  defp host_label(:http_metrics), do: "Local machine (host HTTP metrics)"

  defp host_label(other) when is_atom(other) do
    "Local machine (#{inspect(other)})"
  end
end
