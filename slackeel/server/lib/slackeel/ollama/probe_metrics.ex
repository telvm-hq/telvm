defmodule Slackeel.Ollama.ProbeMetrics do
  @moduledoc false
  # Ephemeral table: last successful integration probe stats per model (RAM, one node).

  @table :slackeel_probe_metrics

  @spec init_table() :: :ok
  def init_table do
    if :ets.whereis(@table) == :undefined do
      _ = :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  @spec record(String.t(), map()) :: :ok
  def record(model, meta) when is_binary(model) and is_map(meta) do
    init_table()

    row =
      Map.merge(meta, %{
        model: model,
        recorded_at: DateTime.utc_now()
      })

    :ets.insert(@table, {model, row})
    :ok
  end

  @spec get(String.t()) :: map() | nil
  def get(model) when is_binary(model) do
    init_table()

    case :ets.lookup(@table, model) do
      [{^model, row}] -> row
      _ -> nil
    end
  end

  @spec all_map() :: %{String.t() => map()}
  def all_map do
    init_table()
    Map.new(:ets.tab2list(@table))
  end
end
