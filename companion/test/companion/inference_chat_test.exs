defmodule Companion.InferenceChatTest do
  use ExUnit.Case, async: true

  alias Companion.InferenceChat

  test "parse_chat_completion_body extracts assistant content" do
    json = ~s({"choices":[{"message":{"role":"assistant","content":"hello"}}]})
    assert InferenceChat.parse_chat_completion_body(json) == {:ok, "hello"}
  end

  test "parse_chat_completion_body maps API error message" do
    json = ~s({"error":{"message":"model not found"}})
    assert InferenceChat.parse_chat_completion_body(json) == {:error, "model not found"}
  end
end
