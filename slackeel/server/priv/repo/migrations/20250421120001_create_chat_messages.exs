defmodule Slackeel.Repo.Migrations.CreateChatMessages do
  use Ecto.Migration

  def change do
    create table(:chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :conversation_id, references(:chat_conversations, type: :binary_id, on_delete: :delete_all),
        null: false

      add :role, :text, null: false
      add :content, :text, null: false, default: ""
      add :model, :text

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:chat_messages, [:conversation_id, :inserted_at])
  end
end
