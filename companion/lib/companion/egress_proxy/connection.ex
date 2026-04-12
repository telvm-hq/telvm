defmodule Companion.EgressProxy.Connection do
  @moduledoc false
  require Logger

  alias Companion.EgressProxy.{History, Policy}

  # Bracketed IPv6 first; else hostname / dotted IPv4 (no ":" in host) so ":port" is not swallowed.
  @connect_re ~r/^CONNECT\s+(\[[^\]]+\]|[^:]+)(?::(\d+))?\s+HTTP\/\d/i
  @get_abs_re ~r/^GET\s+(https?):\/\/([^\/\s]+)([^\s]*)\s+HTTP\/\d/i

  def handle_client(client_sock, workload) do
    opts = [:binary, active: false, packet: :raw]

    case read_http_headers(client_sock, "", opts) do
      {:ok, raw} ->
        [head | _] = String.split(raw, "\r\n", parts: 2)
        dispatch(client_sock, head, raw, workload, opts)

      {:error, reason} ->
        Logger.debug("egress_proxy #{workload.id}: client read error #{inspect(reason)}")
        :gen_tcp.close(client_sock)
    end
  end

  defp dispatch(client_sock, first_line, raw, workload, opts) do
    cond do
      Regex.match?(@connect_re, first_line) ->
        handle_connect(client_sock, first_line, raw, workload, opts)

      Regex.match?(@get_abs_re, first_line) ->
        handle_get_absolute(client_sock, first_line, raw, workload)

      true ->
        deny_json(client_sock, workload, "unknown", :unsupported_method, opts)
    end
  end

  defp handle_connect(client_sock, first_line, raw, workload, opts) do
    case Regex.run(@connect_re, first_line) do
      [_, host, port_s] ->
        handle_connect_parsed(client_sock, raw, workload, opts, host, port_s)

      _ ->
        deny_json(client_sock, workload, "unknown", :malformed_connect, opts)
    end
  end

  defp handle_connect_parsed(client_sock, raw, workload, opts, host, port_s) do
    host = host |> String.trim() |> String.trim("[]")
    port = if port_s && port_s != "", do: String.to_integer(port_s), else: 443

    if Policy.allowed?(host, workload.allow_hosts) do
      case :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false, packet: :raw], 15_000) do
        {:ok, upstream} ->
          Logger.info(
            "egress_proxy CONNECT allowed workload=#{workload.id} target=#{host}:#{port}"
          )

          rest = body_after_headers(raw)

          :gen_tcp.send(
            client_sock,
            "HTTP/1.1 200 Connection Established\r\n\r\n"
          )

          if rest != "" do
            :gen_tcp.send(upstream, rest)
          end

          relay_bidirectional(client_sock, upstream)

        {:error, reason} ->
          Logger.warning("egress_proxy #{workload.id}: upstream connect #{host}:#{port} failed #{inspect(reason)}")
          deny_json(client_sock, workload, host, :upstream_connect_failed, opts)
      end
    else
      deny_json(client_sock, workload, host, :not_on_allowlist, opts)
    end
  end

  defp handle_get_absolute(client_sock, first_line, _raw, workload) do
    case Regex.run(@get_abs_re, first_line) do
      [_, scheme, host, path_qs] ->
        handle_get_absolute_parsed(client_sock, workload, scheme, host, path_qs)

      _ ->
        deny_json(client_sock, workload, "unknown", :malformed_request, [
          :binary,
          active: false,
          packet: :raw
        ])
    end
  end

  defp handle_get_absolute_parsed(client_sock, workload, scheme, host, path_qs) do
    if Policy.allowed?(host, workload.allow_hosts) do
      url = "#{scheme}://#{host}#{path_qs}"

      headers =
        [{"host", host}, {"user-agent", "telvm-egress-proxy/1"}]
        |> maybe_tuple_auth(workload.inject_authorization)

      req = Finch.build(:get, url, headers)

      case Finch.request(req, Companion.EgressProxy.Finch, receive_timeout: 60_000) do
        {:ok, %Finch.Response{status: status, headers: rh, body: body}} ->
          rh_lines = Enum.map(rh, fn {k, v} -> "#{k}: #{v}\r\n" end)
          status_line = "HTTP/1.1 #{status} OK\r\n"
          resp = [status_line, rh_lines, "\r\n", body] |> IO.iodata_to_binary()
          :gen_tcp.send(client_sock, resp)

        {:error, err} ->
          Logger.warning("egress_proxy #{workload.id}: finch GET #{url} #{inspect(err)}")
          deny_json(client_sock, workload, host, :upstream_http_failed, [:binary, active: false, packet: :raw])
      end
    else
      deny_json(client_sock, workload, host, :not_on_allowlist, [:binary, active: false, packet: :raw])
    end

    :gen_tcp.close(client_sock)
  end

  defp maybe_tuple_auth(headers, nil), do: headers
  defp maybe_tuple_auth(headers, ""), do: headers

  defp maybe_tuple_auth(headers, auth) when is_binary(auth) do
    headers ++ [{"authorization", auth}]
  end

  defp deny_json(client_sock, workload, host, reason, _opts) do
    History.record_deny(workload.id, host, reason)

    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      Companion.EgressProxy.topic(),
      {:egress_deny, %{workload_id: workload.id, host: host, reason: reason}}
    )

    body =
      Jason.encode!(%{
        "error" => "egress_denied",
        "workload" => to_string(workload.id),
        "host" => host,
        "reason" => to_string(reason)
      })

    resp =
      [
        "HTTP/1.1 403 Forbidden\r\n",
        "Content-Type: application/json\r\n",
        "Connection: close\r\n",
        "Content-Length: #{byte_size(body)}\r\n",
        "\r\n",
        body
      ]
      |> IO.iodata_to_binary()

    :gen_tcp.send(client_sock, resp)
    :gen_tcp.close(client_sock)
  end

  defp read_http_headers(sock, acc, opts) do
    case :gen_tcp.recv(sock, 0, 30_000) do
      {:ok, data} ->
        acc = acc <> data

        if String.contains?(acc, "\r\n\r\n") do
          {:ok, acc}
        else
          read_http_headers(sock, acc, opts)
        end

      other ->
        other
    end
  end

  defp body_after_headers(raw) do
    case String.split(raw, "\r\n\r\n", parts: 2) do
      [_, rest] -> rest
      _ -> ""
    end
  end

  defp relay_bidirectional(a, b) do
    t1 = Task.async(fn -> copy_until_closed(a, b) end)
    t2 = Task.async(fn -> copy_until_closed(b, a) end)

    _ = Task.await(t1, :infinity)
    _ = Task.await(t2, :infinity)
    :gen_tcp.close(a)
    :gen_tcp.close(b)
  end

  defp copy_until_closed(from, to) do
    case :gen_tcp.recv(from, 0, :infinity) do
      {:ok, data} ->
        case :gen_tcp.send(to, data) do
          :ok -> copy_until_closed(from, to)
          {:error, _} -> :ok
        end

      {:error, _} ->
        :ok
    end
  end
end
