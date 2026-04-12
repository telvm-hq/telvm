defmodule Companion.SavedLabImage do
  use Ecto.Schema
  import Ecto.Changeset

  schema "saved_lab_images" do
    field :ref, :string
    timestamps()
  end

  def changeset(struct, attrs) do
    struct
    |> cast(attrs, [:ref])
    |> validate_required([:ref])
    |> validate_length(:ref, min: 1, max: 2048)
    |> unique_constraint(:ref)
  end
end
