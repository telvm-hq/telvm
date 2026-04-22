defmodule Slackeel.Chat.Conversation do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "chat_conversations" do
    field(:owner_key, :string)
    field(:title, :string)

    has_many(:messages, Slackeel.Chat.Message)

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(conversation, attrs) do
    conversation
    |> cast(attrs, [:owner_key, :title])
    |> validate_required([:owner_key])
  end
end
