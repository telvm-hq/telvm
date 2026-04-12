defmodule Companion.SavedLabImages do
  @moduledoc false

  import Ecto.Query

  alias Companion.Repo
  alias Companion.SavedLabImage
  alias Companion.LabCatalog

  @default_limit 32

  @doc """
  Returns image refs from successful pulls, newest first, excluding refs that match
  the certified catalog (those stay on catalog chips).
  """
  @spec list_refs_for_chips(keyword()) :: [String.t()]
  def list_refs_for_chips(opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)

    catalog_refs =
      LabCatalog.entries()
      |> Enum.map(& &1.ref)
      |> MapSet.new()

    from(s in SavedLabImage,
      order_by: [desc: s.updated_at],
      limit: ^limit,
      select: s.ref
    )
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(catalog_refs, &1))
  end

  @doc """
  Persists a ref after a successful `docker pull` (or upserts `updated_at` if already saved).
  """
  @spec record_pull(String.t()) ::
          {:ok, SavedLabImage.t()} | {:ok, :noop} | {:error, Ecto.Changeset.t()}
  def record_pull(ref) when is_binary(ref) do
    ref = String.trim(ref)

    if ref == "" do
      {:ok, :noop}
    else
      %SavedLabImage{}
      |> SavedLabImage.changeset(%{ref: ref})
      |> Repo.insert(
        on_conflict: {:replace, [:updated_at]},
        conflict_target: :ref
      )
    end
  end
end
