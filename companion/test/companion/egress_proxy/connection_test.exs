defmodule Companion.EgressProxy.ConnectionTest do
  use ExUnit.Case, async: false

  alias Companion.EgressProxy.Connection

  setup do
    start_supervised!(Companion.EgressProxy.History)
    :ok
  end

  test "CONNECT to host not on allowlist returns 403 JSON" do
    {:ok, ls} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true, backlog: 4])

    {:ok, port} = :inet.port(ls)

    workload = %{
      id: "test_wl",
      port: port,
      allow_hosts: ["allowed.example"],
      inject_authorization: nil
    }

    parent = self()

    accept_task =
      Task.async(fn ->
        {:ok, c} = :gen_tcp.accept(ls)
        Connection.handle_client(c, workload)
        send(parent, :handler_done)
      end)

    {:ok, client} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 5000)

    msg = "CONNECT evil.test:443 HTTP/1.1\r\nHost: evil.test\r\n\r\n"
    :ok = :gen_tcp.send(client, msg)

    {:ok, resp} = :gen_tcp.recv(client, 0, 5000)
    assert resp =~ "403"
    assert resp =~ "egress_denied"

    Task.await(accept_task, 10_000)
    assert_receive :handler_done

    :gen_tcp.close(ls)
  end

  test "CONNECT with dotted hostname and port is not malformed_connect" do
    {:ok, ls} =
      :gen_tcp.listen(0, [:binary, packet: :raw, active: false, reuseaddr: true, backlog: 4])

    {:ok, port} = :inet.port(ls)

    workload = %{
      id: "test_wl",
      port: port,
      allow_hosts: ["other.example"],
      inject_authorization: nil
    }

    parent = self()

    accept_task =
      Task.async(fn ->
        {:ok, c} = :gen_tcp.accept(ls)
        Connection.handle_client(c, workload)
        send(parent, :handler_done)
      end)

    {:ok, client} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 5000)

    msg = "CONNECT api.anthropic.com:443 HTTP/1.1\r\nHost: api.anthropic.com:443\r\n\r\n"
    :ok = :gen_tcp.send(client, msg)

    {:ok, resp} = :gen_tcp.recv(client, 0, 5000)
    assert resp =~ "403"
    assert resp =~ "egress_denied"
    refute resp =~ "malformed_connect"
    assert resp =~ "not_on_allowlist"

    Task.await(accept_task, 10_000)
    assert_receive :handler_done

    :gen_tcp.close(ls)
  end
end
