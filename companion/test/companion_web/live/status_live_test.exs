defmodule CompanionWeb.StatusLiveTest do
  use CompanionWeb.ConnCase

  test "GET / renders checks (terminal pre-flight)", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "pre-flight"
    assert html =~ "preflight-rollup"
    assert html =~ "preflight-gating-table"
    assert html =~ "Postgres (Ecto Repo)"
    assert html =~ ~s(href="/topology")
    assert html =~ ~s(href="/machines")
  end

  test "GET /topology renders ASCII diagram view", %{conn: conn} do
    conn = get(conn, ~p"/topology")
    html = html_response(conn, 200)
    assert html =~ "preflight-topology"
    assert html =~ "Docker Desktop"
    assert html =~ ~s(href="/")
  end

  test "GET /machines renders unified machines tab", %{conn: conn} do
    conn = get(conn, ~p"/machines")
    html = html_response(conn, 200)
    assert html =~ "Machines"
    assert html =~ "machines-log"
    assert html =~ "Run pre-flight"
    assert html =~ "destroy all lab"
    assert html =~ "byoi-image-ref"
    assert html =~ "image select"
    assert html =~ "Stock Node"
    assert html =~ "Go HTTP lab"
    assert html =~ "Python HTTP"
    assert html =~ "Ruby HTTP"
    assert html =~ "BusyBox HTTP"
    assert html =~ "warm-machines-section"
    assert html =~ "warm assets"
    assert html =~ "No warm machines"
    assert html =~ "Start &amp; monitor (60s)"
    assert html =~ "mission console"
    assert html =~ "comms"
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
end
