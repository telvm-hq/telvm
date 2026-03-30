defmodule CompanionWeb.ProxyPlugTest do
  use ExUnit.Case, async: true

  alias CompanionWeb.ProxyPlug

  describe "parse_app_path/1" do
    test "default port 3000 with no trailing segments" do
      assert {:ok, %{session_id: "sess_abc", port: 3000, path_segments: []}} =
               ProxyPlug.parse_app_path(["app", "sess_abc"])
    end

    test "default port with extra path under the session" do
      assert {:ok, %{session_id: "sess_abc", port: 3000, path_segments: ["index.html"]}} =
               ProxyPlug.parse_app_path(["app", "sess_abc", "index.html"])
    end

    test "explicit port/N segment" do
      assert {:ok, %{session_id: "sess_abc", port: 5173, path_segments: ["assets", "a.js"]}} =
               ProxyPlug.parse_app_path(["app", "sess_abc", "port", "5173", "assets", "a.js"])
    end

    test "invalid port token falls back to default port and keeps segments in path" do
      assert {:ok, %{session_id: "s", port: 3000, path_segments: ["port", "abc", "x"]}} =
               ProxyPlug.parse_app_path(["app", "s", "port", "abc", "x"])
    end

    test "reject missing session id" do
      assert :error = ProxyPlug.parse_app_path(["app", ""])
      assert :error = ProxyPlug.parse_app_path(["app"])
    end

    test "reject non-app paths" do
      assert :error = ProxyPlug.parse_app_path([])
      assert :error = ProxyPlug.parse_app_path(["api", "v1"])
    end
  end

  describe "call/2" do
    test "forwards to upstream and returns response when http fun succeeds" do
      fake_resp = %{status: 200, headers: [{"content-type", "text/plain"}], body: "hello"}

      http_fun = fn _method, _url, _headers, _body -> {:ok, fake_resp} end

      Application.put_env(:companion, :proxy_http_fun, http_fun)

      on_exit(fn -> Application.delete_env(:companion, :proxy_http_fun) end)

      conn =
        :get
        |> Plug.Test.conn("/app/telvm-vm-mgr-1234/port/3333/index.html")
        |> CompanionWeb.ProxyPlug.call([])

      assert conn.status == 200
      assert conn.halted
      assert conn.resp_body == "hello"
    end

    test "returns 502 when upstream is unreachable" do
      http_fun = fn _method, _url, _headers, _body ->
        {:error, %Mint.TransportError{reason: :econnrefused}}
      end

      Application.put_env(:companion, :proxy_http_fun, http_fun)

      on_exit(fn -> Application.delete_env(:companion, :proxy_http_fun) end)

      conn =
        :get
        |> Plug.Test.conn("/app/sess_1/")
        |> CompanionWeb.ProxyPlug.call([])

      assert conn.status == 502
      assert conn.halted
    end

    test "passes through other paths" do
      conn =
        :get
        |> Plug.Test.conn("/")
        |> CompanionWeb.ProxyPlug.call([])

      refute conn.halted
    end

    test "forwards query string to upstream" do
      test_pid = self()

      http_fun = fn _method, url, _headers, _body ->
        send(test_pid, {:captured_url, url})
        {:ok, %{status: 200, headers: [], body: ""}}
      end

      Application.put_env(:companion, :proxy_http_fun, http_fun)
      on_exit(fn -> Application.delete_env(:companion, :proxy_http_fun) end)

      :get
      |> Plug.Test.conn("/app/container-abc/port/8080/api?foo=bar&baz=1")
      |> CompanionWeb.ProxyPlug.call([])

      assert_received {:captured_url, url}
      assert url == "http://container-abc:8080/api?foo=bar&baz=1"
    end
  end
end
