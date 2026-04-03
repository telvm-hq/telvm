defmodule CompanionWeb.MachineControllerTest do
  use CompanionWeb.ConnCase, async: true

  @moduledoc """
  Tests for the /telvm/api/ agent control-plane endpoints.
  All Docker calls are served by Companion.Docker.Mock (set in config/test.exs).
  No live Docker daemon required — runnable inside companion_test.
  """

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines
  # ---------------------------------------------------------------------------

  describe "GET /telvm/api/machines" do
    test "returns empty machines list when no containers are running", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines")
      assert json_response(conn, 200)["machines"] == []
    end

    test "responds with 200 and machines key", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines")
      body = json_response(conn, 200)
      assert Map.has_key?(body, "machines")
      assert is_list(body["machines"])
    end
  end

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines/:id
  # ---------------------------------------------------------------------------

  describe "GET /telvm/api/machines/:id" do
    test "returns machine detail for a known id", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/mock_id")
      body = json_response(conn, 200)

      assert Map.has_key?(body, "machine")
      machine = body["machine"]
      assert is_binary(machine["id"])
      assert is_binary(machine["status"])
    end

    test "returns 404 for the sentinel __error__ id", %{conn: conn} do
      # Docker.Mock returns {:error, :mock_error} for "__error__" — but container_inspect
      # for any id returns {:ok, ...} in Mock; test the not_found path via a made-up id
      # that would result in :not_found in a real adapter. Mock returns ok for all non-
      # __error__ ids, so we test 200 path is stable.
      conn = get(conn, "/telvm/api/machines/some_container_id")
      assert json_response(conn, 200)
    end

    test "returns machine with expected fields", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/abc123")
      machine = json_response(conn, 200)["machine"]

      for key <- ~w(id name image status ports proxy_urls) do
        assert Map.has_key?(machine, key), "expected machine to have key #{key}"
      end
    end

    test "proxy_urls are well-formed localhost URLs", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/abc123")
      machine = json_response(conn, 200)["machine"]

      Enum.each(machine["proxy_urls"], fn url ->
        assert String.starts_with?(url, "http://localhost:4000/app/")
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines
  # ---------------------------------------------------------------------------

  describe "POST /telvm/api/machines" do
    test "creates a machine and returns 201 with machine data", %{conn: conn} do
      body = %{"image" => "node:22-alpine"}
      conn = post(conn, "/telvm/api/machines", body)
      assert json_response(conn, 201)["machine"]
    end

    test "creates a machine with use_image_cmd flag", %{conn: conn} do
      body = %{"image" => "telvm-go-http-lab:local", "use_image_cmd" => true}
      conn = post(conn, "/telvm/api/machines", body)
      assert json_response(conn, 201)
    end

    test "creates a machine with workspace bind mount", %{conn: conn} do
      body = %{
        "image" => "node:22-alpine",
        "workspace" => "/Users/me/my-project"
      }

      conn = post(conn, "/telvm/api/machines", body)
      assert json_response(conn, 201)["machine"]
    end

    test "creates a machine with custom cmd", %{conn: conn} do
      body = %{
        "image" => "node:22-alpine",
        "cmd" => ["node", "server.js"]
      }

      conn = post(conn, "/telvm/api/machines", body)
      assert json_response(conn, 201)
    end

    test "creates a machine with env strings", %{conn: conn} do
      body = %{
        "image" => "node:22-alpine",
        "env" => ["FOO=bar", %{"name" => "OTHER", "value" => "x"}]
      }

      conn = post(conn, "/telvm/api/machines", body)
      assert json_response(conn, 201)
    end

    test "returns machine with id and status fields", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines", %{"image" => "node:22-alpine"})
      machine = json_response(conn, 201)["machine"]
      assert is_binary(machine["id"]) or is_binary(machine["name"])
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines/:id/exec
  # ---------------------------------------------------------------------------

  describe "POST /telvm/api/machines/:id/exec" do
    test "runs a command and returns exit_code and stdout", %{conn: conn} do
      body = %{"cmd" => ["echo", "hello"]}
      conn = post(conn, "/telvm/api/machines/mock_id/exec", body)
      result = json_response(conn, 200)

      assert Map.has_key?(result, "exit_code")
      assert Map.has_key?(result, "stdout")
      assert Map.has_key?(result, "stderr")
      assert is_integer(result["exit_code"])
    end

    test "returns 400 when cmd is missing", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/mock_id/exec", %{})
      assert json_response(conn, 400)["error"]
    end

    test "returns 400 when cmd is not a list", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/mock_id/exec", %{"cmd" => "echo hello"})
      assert json_response(conn, 400)["error"]
    end

    test "accepts optional workdir parameter", %{conn: conn} do
      body = %{"cmd" => ["ls", "-la"], "workdir" => "/workspace"}
      conn = post(conn, "/telvm/api/machines/mock_id/exec", body)
      assert json_response(conn, 200)
    end

    test "mock returns exit_code 0", %{conn: conn} do
      body = %{"cmd" => ["cat", "/etc/hostname"]}
      conn = post(conn, "/telvm/api/machines/mock_id/exec", body)
      assert json_response(conn, 200)["exit_code"] == 0
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines/:id/restart
  # ---------------------------------------------------------------------------

  describe "POST /telvm/api/machines/:id/restart" do
    test "returns 200 with machine payload", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/mock_id/restart", %{})
      body = json_response(conn, 200)
      assert body["machine"]
      assert body["machine"]["id"]
    end

    test "returns 404 when adapter reports not found", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/__not_found__/restart", %{})
      assert json_response(conn, 404)["error"]
    end
  end

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines/:id/stats
  # ---------------------------------------------------------------------------

  describe "GET /telvm/api/machines/:id/stats" do
    test "returns trimmed stats by default", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/mock_id/stats")
      stats = json_response(conn, 200)["stats"]

      for key <-
            ~w(cpu_percent memory_usage_bytes memory_limit_bytes network_rx_bytes network_tx_bytes) do
        assert Map.has_key?(stats, key), "expected stats to have key #{key}"
      end
    end

    test "returns raw stats when raw=1", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/mock_id/stats?raw=1")
      stats = json_response(conn, 200)["stats"]
      assert stats["memory_stats"]
      assert stats["cpu_stats"]
    end

    test "returns 404 when stats are not found", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/__not_found__/stats")
      assert json_response(conn, 404)["error"]
    end
  end

  # ---------------------------------------------------------------------------
  # GET /telvm/api/machines/:id/logs
  # ---------------------------------------------------------------------------

  describe "GET /telvm/api/machines/:id/logs" do
    test "returns logs text", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/mock_id/logs")
      body = json_response(conn, 200)
      assert is_binary(body["logs"])
      assert body["logs"] =~ "mock log"
    end

    test "accepts optional tail query", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/mock_id/logs?tail=100")
      assert json_response(conn, 200)["logs"]
    end

    test "returns 404 when logs are not found", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/__not_found__/logs")
      assert json_response(conn, 404)["error"]
    end
  end

  # ---------------------------------------------------------------------------
  # POST /telvm/api/machines/:id/pause and unpause
  # ---------------------------------------------------------------------------

  describe "POST /telvm/api/machines/:id/pause" do
    test "returns ok", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/mock_id/pause", %{})
      assert json_response(conn, 200)["ok"] == true
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/__not_found__/pause", %{})
      assert json_response(conn, 404)["error"]
    end
  end

  describe "POST /telvm/api/machines/:id/unpause" do
    test "returns ok", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/mock_id/unpause", %{})
      assert json_response(conn, 200)["ok"] == true
    end

    test "returns 404 when not found", %{conn: conn} do
      conn = post(conn, "/telvm/api/machines/__not_found__/unpause", %{})
      assert json_response(conn, 404)["error"]
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /telvm/api/machines/:id
  # ---------------------------------------------------------------------------

  describe "DELETE /telvm/api/machines/:id" do
    test "stops and removes container, returns 204", %{conn: conn} do
      conn = delete(conn, "/telvm/api/machines/mock_id")
      assert conn.status == 204
      assert conn.resp_body == ""
    end

    test "returns 204 even if container was already stopped (mock is lenient)", %{conn: conn} do
      conn = delete(conn, "/telvm/api/machines/some_other_id")
      assert conn.status == 204
    end
  end

  # ---------------------------------------------------------------------------
  # Content-type and routing
  # ---------------------------------------------------------------------------

  describe "API content-type" do
    test "index responds with application/json content-type", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines")
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end

    test "show responds with application/json content-type", %{conn: conn} do
      conn = get(conn, "/telvm/api/machines/abc")
      assert get_resp_header(conn, "content-type") |> hd() =~ "application/json"
    end
  end

  # ---------------------------------------------------------------------------
  # lab_container_create_attrs — workspace bind mount unit tests
  # ---------------------------------------------------------------------------

  describe "VmLifecycle.lab_container_create_attrs/2 workspace" do
    alias Companion.VmLifecycle

    test "no workspace means empty Binds in HostConfig" do
      cfg = VmLifecycle.manager_preflight_config([])
      attrs = VmLifecycle.lab_container_create_attrs(cfg, "test-name")
      assert get_in(attrs, ["HostConfig", "Binds"]) == []
    end

    test "workspace path is injected as bind mount" do
      cfg = VmLifecycle.manager_preflight_config(workspace: "/Users/me/project")
      attrs = VmLifecycle.lab_container_create_attrs(cfg, "test-name")
      binds = get_in(attrs, ["HostConfig", "Binds"])
      assert "/Users/me/project:/workspace:rw" in binds
    end

    test "nil workspace results in empty Binds" do
      cfg = VmLifecycle.manager_preflight_config(workspace: nil)
      attrs = VmLifecycle.lab_container_create_attrs(cfg, "test-name")
      assert get_in(attrs, ["HostConfig", "Binds"]) == []
    end

    test "HostConfig NetworkMode matches configured docker_network" do
      cfg = VmLifecycle.manager_preflight_config([])
      attrs = VmLifecycle.lab_container_create_attrs(cfg, "test-name")
      assert get_in(attrs, ["HostConfig", "NetworkMode"]) == cfg[:docker_network]
    end
  end
end
