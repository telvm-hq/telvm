defmodule Companion.ClosedAgents.Catalog do
  @moduledoc false

  @type entry :: %{
          compose_service: String.t(),
          label: String.t(),
          proxy_port: pos_integer(),
          vendor_url: String.t(),
          product: String.t(),
          ghcr_package: String.t(),
          tab_key: String.t(),
          card_title: String.t(),
          stack_line: String.t(),
          stack_disclosure: String.t()
        }

  @entries [
    %{
      compose_service: "telvm_closed_claude",
      label: "Claude Code",
      proxy_port: 4001,
      vendor_url: "https://api.anthropic.com/",
      product: "claude-code",
      ghcr_package: "telvm-closed-claude",
      tab_key: "claude",
      card_title: "Node + Claude Code",
      stack_line: "Node 22 · Debian bookworm · Claude Code CLI · egress proxy :4001",
      stack_disclosure: """
      image: telvm-closed-claude (GHCR)
      base: Node 22 on Debian bookworm
      cli: Claude Code (npm global)
      proxy: HTTP(S)_PROXY → companion:4001 (telvm egress workload)
      vendor_probe: https://api.anthropic.com/
      compose_service: telvm_closed_claude
      """
    },
    %{
      compose_service: "telvm_closed_codex",
      label: "Codex",
      proxy_port: 4002,
      vendor_url: "https://api.openai.com/",
      product: "codex",
      ghcr_package: "telvm-closed-codex",
      tab_key: "codex",
      card_title: "Node + Codex",
      stack_line: "Node 22 · Debian bookworm · OpenAI Codex CLI · egress proxy :4002",
      stack_disclosure: """
      image: telvm-closed-codex (GHCR)
      base: Node 22 on Debian bookworm
      cli: Codex CLI (npm global)
      proxy: HTTP(S)_PROXY → companion:4002 (telvm egress workload)
      vendor_probe: https://api.openai.com/
      compose_service: telvm_closed_codex
      """
    }
  ]

  @spec entries() :: [entry()]
  def entries, do: @entries

  @spec by_compose_service(String.t()) :: entry() | nil
  def by_compose_service(name) when is_binary(name) do
    Enum.find(@entries, &(&1.compose_service == name))
  end

  @spec by_product(String.t()) :: entry() | nil
  def by_product(product) when is_binary(product) do
    Enum.find(@entries, &(&1.product == product))
  end

  @spec by_tab_key(String.t()) :: entry() | nil
  def by_tab_key(key) when is_binary(key) do
    Enum.find(@entries, &(&1.tab_key == key))
  end

  @doc "Published image ref (`:main`), same org convention as certified lab images (`TELVM_LAB_GHCR_ORG`)."
  @spec ghcr_main_ref(entry()) :: String.t()
  def ghcr_main_ref(entry) do
    org =
      case System.get_env("TELVM_LAB_GHCR_ORG") do
        nil -> "telvm-hq"
        "" -> "telvm-hq"
        o -> o |> String.trim() |> String.downcase()
      end

    "ghcr.io/#{org}/#{entry.ghcr_package}:main"
  end
end
