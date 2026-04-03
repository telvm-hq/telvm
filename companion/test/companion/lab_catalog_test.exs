defmodule Companion.LabCatalogTest do
  use ExUnit.Case, async: true

  alias Companion.LabCatalog

  describe "entries/0" do
    test "returns five certified GHCR catalog entries only" do
      entries = LabCatalog.entries()
      assert is_list(entries)
      assert length(entries) == 5

      for entry <- entries do
        assert is_atom(entry.id)
        assert is_binary(entry.label)
        assert is_binary(entry.ref)
        assert is_integer(entry.probe_port)
        assert is_boolean(entry.use_image_cmd)
        assert entry.source == :ghcr
        assert Map.has_key?(entry, :container_cmd)
        assert is_boolean(entry.telvm_certified)
        assert entry.telvm_certified == true
        assert is_list(entry.container_env)
        assert is_binary(entry.stack_card)
        assert is_binary(entry.stack_disclosure)
        assert String.contains?(entry.stack_disclosure, "probe:")
        assert is_binary(entry.best_practice)
        assert String.length(entry.best_practice) > 20
      end
    end

    test "image-cmd entries have nil container_cmd" do
      for entry <- LabCatalog.entries(), entry.use_image_cmd == true do
        assert is_nil(entry.container_cmd), "#{entry.id} should have nil container_cmd"
      end
    end

    test "certified GHCR entries are flagged" do
      for id <- [:cert_phoenix, :cert_go, :cert_python, :cert_erlang, :cert_c] do
        entry = LabCatalog.get(id)
        assert entry.source == :ghcr
        assert entry.telvm_certified == true
        assert entry.use_image_cmd == true
        assert entry.ref =~ "ghcr.io/"
        assert entry.ref =~ "telvm-lab-"
        assert entry.ref =~ ":main"
        assert entry.stack_card =~ "_stack.png"
      end
    end
  end

  describe "get/1" do
    test "returns the cert_phoenix entry" do
      entry = LabCatalog.get(:cert_phoenix)
      assert entry.id == :cert_phoenix
      assert entry.ref =~ "telvm-lab-phoenix"
      assert entry.use_image_cmd == true
      assert is_nil(entry.container_cmd)
    end

    test "returns nil for unknown id" do
      assert is_nil(LabCatalog.get(:lab_bun))
      assert is_nil(LabCatalog.get(:unknown_image))
    end
  end

  describe "with_availability/0" do
    test "annotates entries with :available key" do
      entries = LabCatalog.with_availability()

      for entry <- entries do
        assert Map.has_key?(entry, :available)
        assert is_boolean(entry.available)
      end
    end

    test "with mock adapter (empty image list), nothing is available" do
      entries = LabCatalog.with_availability()
      refute Enum.any?(entries, & &1.available)
    end
  end
end
