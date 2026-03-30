# Run inside the companion container (Linux) from /app:
#   mix run --no-start scripts/diagnostics.exs
#
# Use --no-start when `mix phx.server` is already bound to :4000 (avoids :eaddrinuse).
#
# Probes whether anything accepts HTTP on 127.0.0.1:4000 from *inside* the same
# network namespace as Phoenix (matches what "is the server up?" means in-container).

defmodule Telvm.ContainerDiagnostics do
  @moduledoc false

  def run do
    IO.puts([
      "telvm companion diagnostics\n",
      "============================\n",
      "OTP #{:erlang.system_info(:otp_release)} | Elixir #{System.version()}\n",
      "cwd: #{File.cwd!()}\n",
      "MIX_ENV: #{System.get_env("MIX_ENV") || "(unset)"}\n",
      "PORT: #{System.get_env("PORT") || "(unset)"}\n",
      "PHX_SERVER: #{System.get_env("PHX_SERVER") || "(unset)"}\n",
      "DATABASE_URL set?: #{if(System.get_env("DATABASE_URL"), do: "yes", else: "no")}\n"
    ])

    IO.puts("\n--- TCP + minimal HTTP GET http://127.0.0.1:4000/ ---\n")

    case :gen_tcp.connect(~c"127.0.0.1", 4000, [:binary, active: false], 5_000) do
      {:ok, sock} ->
        req = "GET / HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
        :ok = :gen_tcp.send(sock, req)
        body = recv_until_closed(sock, <<>>, 2_000_000)
        :gen_tcp.close(sock)

        preview =
          if byte_size(body) > 12_000,
            do: binary_part(body, 0, 12_000) <> "\n... [truncated]\n",
            else: body

        IO.puts(preview)

      {:error, reason} ->
        IO.puts(
          "CONNECT FAILED: #{inspect(reason)}\n" <>
            "Nothing is accepting TCP on 127.0.0.1:4000 inside this container.\n" <>
            "Typical causes: mix phx.server not started yet (first boot compiles for several minutes),\n" <>
            "crash after assets, or listening only on another interface.\n"
        )
    end

    IO.puts("\n--- Listening TCP ports (ss -lntp) ---\n")
    ss_out = :os.cmd(~c'sh -c "command -v ss >/dev/null && ss -lntp || echo ss-not-installed"')
    IO.puts(List.to_string(ss_out))

    IO.puts("\n--- Docker socket present? ---\n")
    sock_path = "/var/run/docker.sock"
    IO.puts("#{sock_path}: #{if(File.exists?(sock_path), do: "yes", else: "no")}\n")

    IO.puts("--- done ---\n")
  end

  defp recv_until_closed(_sock, acc, max_bytes) when byte_size(acc) >= max_bytes, do: acc

  defp recv_until_closed(sock, acc, max_bytes) do
    case :gen_tcp.recv(sock, 0, 8_000) do
      {:ok, data} ->
        recv_until_closed(sock, acc <> data, max_bytes)

      {:error, :closed} ->
        acc

      {:error, :timeout} ->
        acc

      {:error, other} ->
        acc <> "\n[recv error: #{inspect(other)}]\n"
    end
  end
end

Telvm.ContainerDiagnostics.run()
