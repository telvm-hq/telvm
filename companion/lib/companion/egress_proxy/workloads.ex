defmodule Companion.EgressProxy.Workloads do
  @moduledoc false

  @doc """
  Parses JSON array of workload objects. Each object must include string `id`, integer `port`,
  and `allow_hosts` (list of strings). Optional `authorization_env` names an OS env var whose
  value is sent as the HTTP `Authorization` header on proxied requests (never stored in the DB).
  """
  @spec parse_json(String.t() | nil) :: [map()]
  def parse_json(nil), do: []

  def parse_json(""), do: []

  def parse_json(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, list} when is_list(list) ->
        Enum.flat_map(list, &normalize_entry/1)

      _ ->
        []
    end
  end

  @doc """
  Resolves `authorization_env` on each workload into `inject_authorization` (runtime only).
  """
  @spec attach_secrets([map()]) :: [map()]
  def attach_secrets(workloads) when is_list(workloads) do
    Enum.map(workloads, fn w ->
      inject =
        case Map.get(w, :authorization_env) do
          env when is_binary(env) and env != "" -> System.get_env(env)
          _ -> nil
        end

      Map.put(w, :inject_authorization, inject)
    end)
  end

  defp normalize_entry(%{} = row) do
    id = Map.get(row, "id")
    port = Map.get(row, "port")
    hosts = Map.get(row, "allow_hosts")
    auth_env = Map.get(row, "authorization_env")

    with true <- is_binary(id) and id != "",
         true <- is_integer(port) and port > 0 and port < 65536,
         true <- is_list(hosts) do
      hosts = Enum.map(hosts, &to_string/1)

      base = %{
        id: id,
        port: port,
        allow_hosts: hosts,
        authorization_env: if(is_binary(auth_env) and auth_env != "", do: auth_env, else: nil)
      }

      [base]
    else
      _ -> []
    end
  end

  defp normalize_entry(_), do: []
end
