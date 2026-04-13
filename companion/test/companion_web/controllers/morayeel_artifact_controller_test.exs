defmodule CompanionWeb.MorayeelArtifactControllerTest do
  use CompanionWeb.ConnCase

  @run_id "a1b2c3d4e5f60708"

  setup do
    cfg = Application.fetch_env!(:companion, Companion.MorayeelRunner)
    dir = Keyword.fetch!(cfg, :artifacts_dir)
    run_dir = Path.join(dir, @run_id)
    File.mkdir_p!(run_dir)

    File.write!(
      Path.join(run_dir, "storageState.json"),
      Jason.encode!(%{"cookies" => [], "origins" => []})
    )

    on_exit(fn -> File.rm_rf(run_dir) end)
    :ok
  end

  test "GET storageState.json returns 200 when file exists", %{conn: conn} do
    conn = get(conn, "/telvm/morayeel/artifacts/#{@run_id}/storageState.json")
    assert conn.status == 200
    assert conn.resp_body =~ "cookies"
  end

  test "GET invalid run_id returns 404", %{conn: conn} do
    conn = get(conn, "/telvm/morayeel/artifacts/not-a-hex-id!/storageState.json")
    assert conn.status == 404
  end

  test "GET disallowed filename returns 404", %{conn: conn} do
    conn = get(conn, "/telvm/morayeel/artifacts/#{@run_id}/etc-passwd")
    assert conn.status == 404
  end
end
