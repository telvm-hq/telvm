defmodule Companion.SavedLabImagesTest do
  use Companion.DataCase, async: true

  alias Companion.SavedLabImages

  test "record_pull inserts and list_refs_for_chips returns newest non-catalog refs" do
    assert SavedLabImages.list_refs_for_chips() == []

    unique = "ghcr.io/telvm-hq/saved-lab-test:#{System.unique_integer([:positive])}"
    assert {:ok, _} = SavedLabImages.record_pull("  #{unique}  ")
    assert unique in SavedLabImages.list_refs_for_chips()

    assert {:ok, _} = SavedLabImages.record_pull(unique)
    assert unique in SavedLabImages.list_refs_for_chips()
  end

  test "list_refs_for_chips omits certified catalog refs" do
    catalog_ref = hd(Companion.LabCatalog.entries()).ref
    assert {:ok, _} = SavedLabImages.record_pull(catalog_ref)
    refute catalog_ref in SavedLabImages.list_refs_for_chips()
  end
end
