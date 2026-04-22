defmodule Slackeel.Chat.Message do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_messages" do
    field(:role, :string)
    field(:content, :string, default: "")
    field(:model, :string)
    belongs_to(:conversation, Slackeel.Chat.Conversation, type: :binary_id)

    timestamps(updated_at: false, type: :utc_datetime_usec)
  end

  def changeset(message, attrs) do
    message
    |> cast(attrs, [:conversation_id, :role, :content, :model])
    |> validate_required([:conversation_id, :role])
    |> validate_inclusion(:role, ["user", "assistant"])
  end
end
