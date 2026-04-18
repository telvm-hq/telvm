defmodule SpeedeelWeb.MinigamesLiveTest do
  use ExUnit.Case, async: true
  import Phoenix.ConnTest

  @endpoint SpeedeelWeb.Endpoint

  test "GET /minigames renders catacombs hub" do
    conn = build_conn() |> get("/minigames")
    html = html_response(conn, 200)
    assert html =~ "Hospitality Catacombs"
    assert html =~ "Daytona"
    assert html =~ "speedeel-dungeon-stage"
    assert html =~ "github.com/daytonaio/daytona/issues/2390"
    assert html =~ "github.com/e2b-dev/E2B/issues/646"
    assert html =~ "github.com/modal-labs/modal-examples/issues/1264"
    assert html =~ "github.com/loft-sh/vcluster/issues/3805"
    assert html =~ "Loft Labs"
  end
end
