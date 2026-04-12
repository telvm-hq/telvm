defmodule Companion.ClosedAgents.Verify do
  @moduledoc false

  @dirteel_bin "/usr/local/bin/dirteel"

  @doc """
  Runs an egress probe via companion (`dirteel egress-probe` when installed in the
  container, otherwise `curl` through the same proxy), then `apt-get update`.

  Returns `{:ok, :verified}` or `{:error, step, detail}`.

  Set `TELVM_CLOSED_SOAK_VERBOSE=1` on the companion container for noisier probe output
  in error details (Engine mux combines stdout/stderr into the payload we receive).
  """
  @spec run(String.t(), pos_integer(), String.t()) :: {:ok, :verified} | {:error, atom(), String.t()}
  def run(container_id, proxy_port, vendor_url)
      when is_binary(container_id) and is_integer(proxy_port) and is_binary(vendor_url) do
    docker = Companion.Docker.impl()

    probe = egress_probe_shell(proxy_port, vendor_url)
    max_out = if soak_verbose?(), do: 900, else: 520

    case docker.container_exec_with_exit(container_id, ["sh", "-c", probe], []) do
      {:ok, %{exit_code: 0}} ->
        run_apt(docker, container_id)

      {:ok, %{exit_code: code, stdout: out}} ->
        detail =
          "egress probe exit #{code} | engine output (stdout/stderr): " <>
            String.slice(String.trim(to_string(out)), 0, max_out)

        {:error, :curl, detail}

      {:error, reason} ->
        {:error, :curl, inspect(reason)}
    end
  end

  defp egress_probe_shell(proxy_port, vendor_url) do
    inner =
      "if [ -x #{@dirteel_bin} ]; then #{@dirteel_bin} egress-probe --proxy-host companion --proxy-port #{proxy_port} --https-url #{shell_single_quoted(vendor_url)}; else #{curl_command(proxy_port, vendor_url)}; fi"

    if soak_verbose?(), do: "( #{inner} ) 2>&1", else: inner
  end

  defp shell_single_quoted(s) when is_binary(s) do
    "'" <> String.replace(s, "'", "'\"'\"'") <> "'"
  end

  defp curl_command(proxy_port, vendor_url) do
    proxy = "http://companion:#{proxy_port}"

    if soak_verbose?() do
      # -v to stderr; 2>&1 so Docker exec mux captures it for the operator panel.
      "curl -v --max-time 45 -o /dev/null --proxy #{proxy} #{vendor_url} 2>&1"
    else
      "curl -sS -o /dev/null --max-time 45 --proxy #{proxy} #{vendor_url}"
    end
  end

  defp soak_verbose? do
    case System.get_env("TELVM_CLOSED_SOAK_VERBOSE") do
      v when v in ~w(1 true TRUE yes YES on ON) -> true
      _ -> false
    end
  end

  defp run_apt(docker, container_id) do
    apt =
      "export DEBIAN_FRONTEND=noninteractive && apt-get update -qq"

    max_out = if soak_verbose?(), do: 900, else: 520

    case docker.container_exec_with_exit(container_id, ["sh", "-c", apt], []) do
      {:ok, %{exit_code: 0}} ->
        {:ok, :verified}

      {:ok, %{exit_code: code, stdout: out}} ->
        detail =
          "apt-get exit #{code} | engine output (stdout/stderr): " <>
            String.slice(String.trim(to_string(out)), 0, max_out)

        {:error, :apt, detail}

      {:error, reason} ->
        {:error, :apt, inspect(reason)}
    end
  end
end
