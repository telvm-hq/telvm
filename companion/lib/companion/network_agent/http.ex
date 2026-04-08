defmodule Companion.NetworkAgent.HTTP do
  @moduledoc false
  @behaviour Companion.NetworkAgent

  @finch Companion.Finch
  @receive_timeout 8_000

  @impl true
  def health(base_url, token), do: get(base_url, "/health", token)

  @impl true
  def ics_hosts(base_url, token), do: get(base_url, "/ics/hosts", token)

  @impl true
  def ics_status(base_url, token), do: get(base_url, "/ics/status", token)

  @impl true
  def ics_diagnostics(base_url, token), do: get(base_url, "/ics/diagnostics", token)

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
