defmodule Companion.EgressProxy.Policy do
  @moduledoc false

  @doc """
  Returns true if `host` (lowercase hostname, no port) is allowed by `allow_hosts`.

  Rules:
  - Exact match after normalization.
  - If a rule starts with `.`, it is a suffix match (e.g. `.anthropic.com` matches `api.anthropic.com`).
  """
  @spec allowed?(String.t(), [String.t()]) :: boolean()
  def allowed?(host, allow_hosts) when is_binary(host) and is_list(allow_hosts) do
    h = String.downcase(host) |> String.trim()

    Enum.any?(allow_hosts, fn rule ->
      rule = String.trim(rule)
      rule = String.downcase(rule)

      cond do
        rule == "" ->
          false

        String.starts_with?(rule, ".") ->
          h == String.trim_leading(rule, ".") or String.ends_with?(h, rule)

        true ->
          h == rule
      end
    end)
  end

  def allowed?(_, _), do: false
end
