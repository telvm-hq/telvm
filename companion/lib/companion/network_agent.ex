defmodule Companion.NetworkAgent do
  @moduledoc """
  Behaviour for communicating with the telvm network agent (PowerShell ICS service).

  The network agent runs on the Windows gateway PC and exposes ICS state,
  host discovery, and diagnostics over HTTP — mirroring how `Companion.ClusterNode`
  abstracts the Zig node agent on Linux hosts.
  """

  @type base_url :: String.t()
  @type token :: String.t()

  @callback health(base_url(), token()) :: {:ok, map()} | {:error, term()}
  @callback ics_hosts(base_url(), token()) :: {:ok, map()} | {:error, term()}
  @callback ics_status(base_url(), token()) :: {:ok, map()} | {:error, term()}
  @callback ics_diagnostics(base_url(), token()) :: {:ok, map()} | {:error, term()}

  @doc false
  def impl do
    Application.get_env(:companion, :network_agent_adapter, Companion.NetworkAgent.HTTP)
  end
end
