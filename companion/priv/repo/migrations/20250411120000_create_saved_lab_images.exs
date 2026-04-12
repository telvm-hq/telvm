defmodule Companion.Repo.Migrations.CreateSavedLabImages do
  use Ecto.Migration

  def change do
    create table(:saved_lab_images) do
      add :ref, :text, null: false
      timestamps()
    end

    create unique_index(:saved_lab_images, [:ref])
  end
end
