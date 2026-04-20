defmodule SlackeelWeb.PageControllerTest do
  use SlackeelWeb.ConnCase

  test "GET / redirects to /preflight", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/preflight"
  end
end
