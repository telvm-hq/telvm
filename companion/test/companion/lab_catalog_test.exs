defmodule Companion.LabCatalogTest do
  use ExUnit.Case, async: true

  alias Companion.LabCatalog

  describe "entries/0" do
    test "returns 5 catalog entries" do
      entries = LabCatalog.entries()
      assert is_list(entries)
      assert length(entries) == 5

      for entry <- entries do
        assert is_atom(entry.id)
        assert is_binary(entry.label)
        assert is_binary(entry.ref)
        assert is_integer(entry.probe_port)
        assert is_boolean(entry.use_image_cmd)
        assert entry.source in [:hub, :local_build]
        assert Map.has_key?(entry, :container_cmd)
      end
    end

    test "all inline-cmd entries have a non-nil container_cmd list" do
      for entry <- LabCatalog.entries(), entry.use_image_cmd == false do
        assert is_list(entry.container_cmd), "#{entry.id} should have a container_cmd list"
      end
    end

    test "image-cmd entries have nil container_cmd" do
      for entry <- LabCatalog.entries(), entry.use_image_cmd == true do
        assert is_nil(entry.container_cmd), "#{entry.id} should have nil container_cmd"
      end
    end
  end

  describe "get/1" do
    test "returns the lab_bun entry" do
      entry = LabCatalog.get(:lab_bun)
      assert entry.id == :lab_bun
      assert entry.ref == "oven/bun:1-alpine"
      assert entry.use_image_cmd == false
      assert is_list(entry.container_cmd)
    end

    test "returns the lab_go entry" do
      entry = LabCatalog.get(:lab_go)
      assert entry.id == :lab_go
      assert entry.ref == "golang:1.23-alpine"
      assert entry.use_image_cmd == false
      assert is_list(entry.container_cmd)
    end

    test "returns the lab_python_uv entry" do
      entry = LabCatalog.get(:lab_python_uv)
      assert entry.id == :lab_python_uv
      assert entry.ref == "python:3.12-slim-bookworm"
      assert is_list(entry.container_cmd)
    end

    test "returns the lab_elixir entry" do
      entry = LabCatalog.get(:lab_elixir)
      assert entry.id == :lab_elixir
      assert entry.ref == "elixir:1.18-alpine"
    end

    test "returns the lab_c entry" do
      entry = LabCatalog.get(:lab_c)
      assert entry.id == :lab_c
      assert entry.ref == "gcc:14-bookworm"
    end

    test "returns nil for unknown id" do
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
