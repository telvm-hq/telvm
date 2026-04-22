defmodule Slackeel.ChatTest do
  use SlackeelWeb.ConnCase

  alias Slackeel.Chat

  test "conversations are scoped by owner_key", %{conn: _conn} do
    owner_a = Ecto.UUID.generate()
    owner_b = Ecto.UUID.generate()

    {:ok, conv_a} = Chat.create_conversation(owner_a, %{})
    {:ok, _} = Chat.create_conversation(owner_b, %{})

    assert [_] = Chat.list_conversations(owner_a)
    assert Chat.get_conversation(owner_a, to_string(conv_a.id)) == {:ok, conv_a}
    assert Chat.get_conversation(owner_b, to_string(conv_a.id)) == {:error, :not_found}
  end

  test "default_conversation_title counts existing threads for owner" do
    owner = Ecto.UUID.generate()
    assert Chat.default_conversation_title(owner) == "Conversation 1"

    {:ok, c1} =
      Chat.create_conversation(owner, %{title: Chat.default_conversation_title(owner)})

    assert c1.title == "Conversation 1"
    assert Chat.default_conversation_title(owner) == "Conversation 2"
  end

  test "append_user_and_assistant persists ordered messages", %{conn: _conn} do
    owner = Ecto.UUID.generate()
    {:ok, conv} = Chat.create_conversation(owner, %{})

    assert {:ok, {_u, a}} =
             Chat.append_user_and_assistant(to_string(conv.id), "hello world", "llama3.2:1b")

    msgs = Chat.messages_for_liveview(to_string(conv.id))
    assert length(msgs) == 2
    assert Enum.at(msgs, 0).role == "user"
    assert Enum.at(msgs, 0).content == "hello world"
    assert Enum.at(msgs, 1).role == "assistant"
    assert Enum.at(msgs, 1).id == a.id
    assert Enum.at(msgs, 1).content == ""

    assert {:ok, _} = Chat.update_message_content!(a.id, "done")

    asst =
      Chat.list_messages(to_string(conv.id))
      |> Enum.find(&(&1.role == "assistant"))

    assert asst.content == "done"
  end
end
