defmodule SlackeelWeb.ReceiptsLiveTest do
  use SlackeelWeb.ConnCase

  import Phoenix.LiveViewTest

  test "GET /receipts renders Node and Python SDK issue tables", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/receipts")

    assert has_element?(view, "h1", "Receipts")
    html = render(view)
    assert html =~ "slackapi/node-slack-sdk"
    assert html =~ "slackapi/python-slack-sdk"
    refute html =~ "slackapi/bolt-js"
    assert html =~ "github.com/slackapi/node-slack-sdk/issues/2359"
    assert html =~ "github.com/slackapi/python-slack-sdk/issues/1826"
    assert html =~ "2025-09-04"
    assert html =~ "2026-01-30"
    assert html =~ "lg:grid-cols-2"
    assert has_element?(view, "#receipts-sdk-grid")
    assert has_element?(view, "#receipts-node-sdk")
    assert has_element?(view, "#receipts-python-sdk")

    assert length(SlackeelWeb.ReceiptsLive.node_slack_sdk_receipts()) == 5
    assert length(SlackeelWeb.ReceiptsLive.python_slack_sdk_receipts()) == 5
    assert length(SlackeelWeb.ReceiptsLive.all_receipts()) == 10

    first_node = hd(SlackeelWeb.ReceiptsLive.node_slack_sdk_receipts())
    assert %{opened_on: %Date{}} = first_node
  end
end
