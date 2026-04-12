defmodule Companion.EgressProxy do
  @moduledoc """
  Per-workload HTTP forward proxy (CONNECT + minimal absolute-URI GET) supervised under OTP.

  Configure via `Application.get_env(:companion, Companion.EgressProxy)` — see `config/runtime.exs`.
  """

  def topic, do: "egress_proxy:updates"

  defdelegate parse_workloads_json(json), to: Companion.EgressProxy.Workloads, as: :parse_json

  @doc """
  Returns dashboard-friendly rows: workload id, internal proxy URL, allow_hosts digest, recent denies.
  """
  def snapshot do
    cfg = Application.get_env(:companion, __MODULE__) || []
    enabled = Keyword.get(cfg, :enabled, false)
    workloads = Keyword.get(cfg, :workloads, [])

    denies =
      if enabled and Process.whereis(Companion.EgressProxy.History) do
        Companion.EgressProxy.History.recent_deny_entries()
      else
        []
      end

    rows =
      Enum.map(workloads, fn w ->
        allow_digest =
          w.allow_hosts
          |> Enum.sort()
          |> Enum.join(", ")
          |> then(fn s -> String.slice(s, 0, 120) end)

        %{
          id: w.id,
          port: w.port,
          internal_url: "http://companion:#{w.port}",
          allow_hosts: w.allow_hosts,
          allow_digest: allow_digest,
          inject_auth_configured: w.inject_authorization not in [nil, ""]
        }
      end)

    %{enabled: enabled, workloads: rows, recent_denies: denies}
  end
end
