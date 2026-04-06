defmodule Companion.LanTarget do
  @moduledoc """
  Optional LAN host targeting for probes and future dirteel-driven provisioning.

  Configure via `TELVM_LAN_TARGET_HOST` and `TELVM_LAN_TARGET_SSH_PORT` (see repo `.env.example`).
  """

  @spec settings() :: keyword()
  def settings do
    Application.get_env(:companion, :lan_target, [])
  end

  @spec host() :: String.t() | nil
  def host do
    case settings()[:host] do
      s when is_binary(s) ->
        s = String.trim(s)
        if s == "", do: nil, else: s

      _ ->
        nil
    end
  end

  @spec ssh_port() :: pos_integer()
  def ssh_port do
    settings()[:ssh_port] || 22
  end

  @spec configured?() :: boolean()
  def configured? do
    host() != nil
  end
end
