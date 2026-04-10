defmodule Companion.NetworkAgentHosts do
  @moduledoc false

  @doc """
  Coerces `/ics/hosts` JSON `hosts` field into a list of host maps.

  JSON objects decode to Elixir maps; an empty object `%{}` is truthy and must
  not be passed to code expecting a list.
  """
  @spec normalize(term()) :: [map()]
  def normalize(raw) do
    case raw do
      nil ->
        []

      list when is_list(list) ->
        Enum.filter(list, &is_map/1)

      map when is_map(map) ->
        cond do
          map_size(map) == 0 -> []
          Map.has_key?(map, "ip") -> [map]
          true -> []
        end

      _ ->
        []
    end
  end
end
