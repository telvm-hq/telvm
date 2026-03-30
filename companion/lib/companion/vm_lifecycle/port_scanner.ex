defmodule Companion.VmLifecycle.PortScanner do
  @moduledoc false

  @listen_state "0A"

  @doc """
  Exec `cat /proc/net/tcp` inside the container and return listening ports.
  """
  def scan_ports(container_id) do
    docker = Companion.Docker.impl()

    # Read both IPv4 and IPv6 tables in one exec — Go and other runtimes often
    # bind only an IPv6 dual-stack socket (appearing in tcp6, not tcp).
    case docker.container_exec(container_id, ["cat", "/proc/net/tcp", "/proc/net/tcp6"], []) do
      {:ok, output} -> {:ok, parse_proc_net_tcp(output)}
      {:error, _} = e -> e
    end
  end

  @doc """
  Parse `/proc/net/tcp` and/or `/proc/net/tcp6` text and extract listening port numbers.

  Format per line (both files share this structure):
    sl  local_address rem_address  st ...
     0: 00000000:0D05 00000000:0000 0A ...          (tcp  — IPv4, 8-char IP)
     0: 00000000000000000000000000000000:0D05 … 0A … (tcp6 — IPv6, 32-char IP)

  Field index 1 is local_address (IP:port in hex), field index 3 is state.
  State 0A = LISTEN. The port is always the last 4 hex chars after the colon,
  regardless of whether the IP is IPv4 or IPv6.
  """
  def parse_proc_net_tcp(text) when is_binary(text) do
    text
    |> String.split("\n", trim: true)
    |> Enum.flat_map(&parse_line/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp parse_line(line) do
    parts = String.split(String.trim(line))

    with [_, local_addr, _rem_addr, state | _] <- parts,
         true <- state == @listen_state,
         port when port > 0 <- extract_port(local_addr) do
      [port]
    else
      _ -> []
    end
  end

  defp extract_port(addr) do
    case String.split(addr, ":") do
      [_ip, port_hex] ->
        case Integer.parse(port_hex, 16) do
          {port, ""} -> port
          _ -> 0
        end

      _ ->
        0
    end
  end
end
