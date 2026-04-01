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
    assert html =~ "/health"
    assert html =~ "telvm/api/fyi"
  end

  test "GET /topology redirects to /health", %{conn: conn} do
    conn = get(conn, ~p"/topology")
    assert redirected_to(conn) == "/health"
  end

  test "GET /warm renders warm assets layout", %{conn: conn} do
    conn = get(conn, ~p"/warm")
    html = html_response(conn, 200)
    assert html =~ "Warm assets"
    assert html =~ "warm-machines-section"
    assert html =~ "warm assets"
    assert html =~ "No warm machines"
    assert html =~ "endpoints"
    assert html =~ "lab-preview-frame"
    assert html =~ "No preview yet"
    assert html =~ ~s(href="/warm")
    assert html =~ ~s(href="/machines")
    assert html =~ ~s(href="/health")
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
    assert html =~ "Node + Bun"
    assert html =~ "Elixir + mix"
    assert html =~ "python + uv"
    assert html =~ "C + gcc"
    assert html =~ "Extended soak (60s)"
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
end
