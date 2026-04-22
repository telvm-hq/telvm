defmodule SlackeelWeb.Plugs.EnsureChatOwner do
  @moduledoc """
  Assigns a stable anonymous `chat_owner_id` in the session so persisted chats can be scoped per browser.
  """
  import Plug.Conn

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case get_session(conn, :chat_owner_id) do
      id when is_binary(id) and id != "" ->
        conn

      _ ->
        put_session(conn, :chat_owner_id, Ecto.UUID.generate())
    end
  end
end
