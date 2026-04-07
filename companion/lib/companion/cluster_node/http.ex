defmodule Companion.ClusterNode.HTTP do
  @moduledoc false
  @behaviour Companion.ClusterNode

  @finch Companion.Finch
  @receive_timeout 5_000

  @impl true
  def health(base_url, token) do
    get(base_url, "/health", token)
  end

  @impl true
  def docker_version(base_url, token) do
    get(base_url, "/docker/version", token)
  end

  @impl true
  def docker_containers(base_url, token) do
    case get(base_url, "/docker/containers", token) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, other} -> {:error, {:unexpected_shape, other}}
      err -> err
    end
  end

  defp get(base_url, path, token) do
    url = String.trim_trailing(base_url, "/") <> path

    headers =
      if token != "" do
        [{"authorization", "Bearer #{token}"}]
      else
        []
      end

    req = Finch.build(:get, url, headers)

    case Finch.request(req, @finch, receive_timeout: @receive_timeout) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        Jason.decode(body)

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
