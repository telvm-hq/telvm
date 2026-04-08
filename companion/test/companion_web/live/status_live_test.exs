defmodule CompanionWeb.StatusLiveTest do
  use CompanionWeb.ConnCase

  test "GET / redirects to /health", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/health"
  end

  test "GET /health renders stack pre-flight (terminal)", %{conn: conn} do
    conn = get(conn, ~p"/health")
    html = html_response(conn, 200)
    assert html =~ "pre-flight"
    assert html =~ "preflight-rollup"
    assert html =~ "preflight-gating-table"
    assert html =~ "Postgres (Ecto Repo)"
    assert html =~ ~s(href="/warm")
    assert html =~ ~s(href="/machines")
    assert html =~ ~s(href="/agent")
    assert html =~ "/health"
    assert html =~ "api reference"
  end

  test "GET /topology redirects to /warm", %{conn: conn} do
    conn = get(conn, ~p"/topology")
    assert redirected_to(conn) == "/warm"
  end

  test "GET /agent renders agent setup preflight panel", %{conn: conn} do
    conn = get(conn, ~p"/agent")
    html = html_response(conn, 200)
    assert html =~ "telvm · agent setup"
    assert html =~ "agent-inference-preflight"
    assert html =~ ~s(id="agent-goose-panel")
    assert html =~ ~s(id="agent-chat-panel")
    assert html =~ ~s(phx-submit="test_inference_endpoint")
    assert html =~ ~s(phx-click="set_agent_chat_tab")
    assert html =~ ~s(phx-submit="start_agent_chat")
    assert html =~ ~s(phx-submit="send_goose_chat")
    assert html =~ ~s(id="agent-goose-chat")
    assert html =~ ~s(id="agent-goose-health-line")
    assert html =~ ~s(href="/agent")
    assert html =~ ~s(href="/warm")
    assert html =~ ~s(href="/machines")
  end

  test "GET /warm renders warm assets layout and network blueprint", %{conn: conn} do
    conn = get(conn, ~p"/warm")
    html = html_response(conn, 200)
    assert html =~ "Warm assets"
    assert html =~ "warm-machines-section"
    assert html =~ "warm assets"
    assert html =~ "No warm machines"
    # "endpoints" appears only when at least one warm machine row exists
    assert html =~ "telvm · warm assets"
    assert html =~ "Network blueprint"
    assert html =~ "telvm_default"
    assert html =~ "/telvm/api"
    assert html =~ "lab-preview-frame"
    assert html =~ "No preview yet"
    assert html =~ ~s(href="/warm")
    assert html =~ ~s(href="/machines")
    assert html =~ ~s(href="/health")
    refute html =~ ~s(href="/topology")
  end

  test "GET /machines renders mission console without warm list", %{conn: conn} do
    conn = get(conn, ~p"/machines")
    html = html_response(conn, 200)
    assert html =~ "Machines"
    assert html =~ "lab-verify-card"
    assert html =~ "lab-image-section"
    assert html =~ "lab-catalog-grid"
    assert html =~ "Verify (pre-flight + 15s soak)"
    assert html =~ "destroy all lab"
    assert html =~ "byoi-image-ref"
    assert html =~ "image &amp; runtime"
    assert html =~ "Phoenix (certified)"
    assert html =~ "Go (certified)"
    assert html =~ "lab-stacks"
    assert html =~ "lab-stack-disclosure"
    assert html =~ "stack disclosure"
    assert html =~ "Bandit"
    refute html =~ "Node + Bun"
    assert html =~ "Certified soak (60s)"
    assert html =~ "mission console"
    refute html =~ "warm-machines-section"
    refute html =~ "id=\"lab-preview-frame\""
    refute html =~ "machines-log"
    refute html =~ ">comms<"
  end

  test "GET /images redirects to /machines", %{conn: conn} do
    conn = get(conn, ~p"/images")
    assert redirected_to(conn) == "/machines"
  end

  test "GET /vm-manager-preflight redirects to /machines", %{conn: conn} do
    conn = get(conn, ~p"/vm-manager-preflight")
    assert redirected_to(conn) == "/machines"
  end

  test "GET /certificate redirects to /machines", %{conn: conn} do
    conn = get(conn, ~p"/certificate")
    assert redirected_to(conn) == "/machines"
  end

  test "GET /telvm/api/fyi returns markdown", %{conn: conn} do
    conn = get(conn, ~p"/telvm/api/fyi")
    assert conn.status == 200
    assert hd(get_resp_header(conn, "content-type")) =~ "text/markdown"
    assert conn.resp_body =~ "TELVM"
  end

  test "machines LiveView defines certified soak handler" do
    path = Path.expand("../../../lib/companion_web/live/status_live.ex", __DIR__)
    source = File.read!(path)

    assert source =~ ~s(phx-click="certified_extended_soak")
    assert source =~ "handle_event(\"certified_extended_soak\""
  end

  test "warm assets LiveView defines restart / pause / resume handlers" do
    path = Path.expand("../../../lib/companion_web/live/status_live.ex", __DIR__)
    source = File.read!(path)

    assert source =~ ~s(phx-click="restart_machine")
    assert source =~ ~s(phx-click="pause_machine")
    assert source =~ ~s(phx-click="unpause_machine")
    assert source =~ ~s(phx-click="destroy_machine")
    assert source =~ "handle_event(\"restart_machine\""
    assert source =~ "handle_event(\"pause_machine\""
    assert source =~ "handle_event(\"unpause_machine\""
    assert source =~ "handle_event(\"destroy_machine\""
  end
end
