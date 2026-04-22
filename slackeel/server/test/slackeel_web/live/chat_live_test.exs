defmodule SlackeelWeb.ChatLiveTest do
  use SlackeelWeb.ConnCase

  import Phoenix.LiveViewTest,
    only: [
      live: 2,
      element: 2,
      element: 3,
      render: 1,
      render_change: 2,
      render_click: 1,
      has_element?: 3
    ]

  alias Slackeel.Chat
  alias Slackeel.Ollama.HotRegistry

  test "GET /chat renders chat shell and nav summary with headroom", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/chat")

    assert has_element?(view, "h1", "Chat")
    html = render(view)
    assert html =~ "Summary"
    assert html =~ "Headroom"
    assert html =~ "GiB"
  end

  test "typing @qwen at end of line shows manifest model suggestions", %{conn: conn} do
    owner = Ecto.UUID.generate()
    {:ok, conv} = Chat.create_conversation(owner, %{})
    conn = Plug.Test.init_test_session(conn, %{"chat_owner_id" => owner})

    {:ok, view, _html} = live(conn, ~p"/chat/#{conv.id}")

    html =
      view
      |> element("#chat-input")
      |> render_change(%{"content" => "hello @qwen"})

    assert html =~ "qwen2.5"
  end

  test "warm model buttons update from PubSub; pick and clear selection", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/chat")

    assert html =~ "Warm &amp; ready"

    row = %{
      tag: "slackeel_chat_lv_warm_test",
      want: true,
      status: :ready,
      margin_bytes: 1,
      last_used: nil,
      load_pct: 100,
      load_status: "ready",
      unload_busy: false
    }

    snap = %{
      budget_bytes: 2_147_483_648,
      used_bytes: 1,
      rows: [row],
      ollama_ps: []
    }

    Phoenix.PubSub.broadcast(Slackeel.PubSub, HotRegistry.pubsub_topic(), {:hot_models, snap})

    html = render(view)
    assert html =~ "slackeel_chat_lv_warm_test"

    view
    |> element("button[phx-value-tag=slackeel_chat_lv_warm_test]")
    |> render_click()

    html = render(view)
    assert html =~ "Next send →"
    assert html =~ "Clear pick"

    view
    |> element("button[phx-click=clear_model_pick]")
    |> render_click()

    refute render(view) =~ "Next send →"
  end

  test "GET /chat/:id shows persisted messages for session owner", %{conn: conn} do
    owner = Ecto.UUID.generate()
    {:ok, conv} = Chat.create_conversation(owner, %{})

    assert {:ok, _} =
             Chat.append_user_and_assistant(to_string(conv.id), "hello db", "qwen2.5:0.5b")

    conn = Plug.Test.init_test_session(conn, %{"chat_owner_id" => owner})
    {:ok, _view, html} = live(conn, ~p"/chat/#{conv.id}")
    assert html =~ "hello db"
  end

  test "New chat creates a conversation and navigates", %{conn: conn} do
    owner = Ecto.UUID.generate()
    conn = Plug.Test.init_test_session(conn, %{"chat_owner_id" => owner})
    before = length(Chat.list_conversations(owner))

    {:ok, view, _html} = live(conn, ~p"/chat")

    view |> element("button", "New chat") |> render_click()
    {to, _flash} = Phoenix.LiveViewTest.assert_redirect(view)

    assert String.match?(
             to,
             ~r"^/chat/[0-9a-f-]{8}-[0-9a-f-]{4}-[0-9a-f-]{4}-[0-9a-f-]{4}-[0-9a-f-]{12}$"
           )

    assert length(Chat.list_conversations(owner)) == before + 1
  end
end
