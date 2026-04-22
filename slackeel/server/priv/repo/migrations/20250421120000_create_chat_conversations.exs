defmodule Slackeel.Repo.Migrations.CreateChatConversations do
  use Ecto.Migration

  def change do
    create table(:chat_conversations, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :owner_key, :text, null: false
      add :title, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:chat_conversations, [:owner_key])
    create index(:chat_conversations, [:owner_key, :updated_at])
  end
end
