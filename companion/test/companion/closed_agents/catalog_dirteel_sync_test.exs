defmodule Companion.ClosedAgents.CatalogDirteelSyncTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Companion.ClosedAgents.Catalog

  defp profiles_path do
    case System.get_env("TELVM_DIRTEEL_PROFILES") do
      p when is_binary(p) and p != "" -> p
      _ -> Path.expand("../../../../agents/dirteel/profiles/closed_images.json", __DIR__)
    end
  end

  test "agents/dirteel/profiles/closed_images.json matches ClosedAgents.Catalog" do
    path = profiles_path()

    assert File.exists?(path),
           "missing #{path} — add profiles, mount ./agents in Docker, or set TELVM_DIRTEEL_PROFILES"

    list = path |> File.read!() |> Jason.decode!()
    assert is_list(list)

    catalog = Catalog.entries()
    assert length(list) == length(catalog)

    by_service = Map.new(list, &{&1["compose_service"], &1})

    for e <- catalog do
      p = Map.fetch!(by_service, e.compose_service)

      assert p["proxy_port"] == e.proxy_port,
             "proxy_port mismatch for #{e.compose_service}: json=#{inspect(p["proxy_port"])} catalog=#{e.proxy_port}"

      assert p["vendor_url"] == e.vendor_url,
             "vendor_url mismatch for #{e.compose_service}"

      assert p["product"] == e.product,
             "product mismatch for #{e.compose_service}"

      assert p["ghcr_package"] == e.ghcr_package,
             "ghcr_package mismatch for #{e.compose_service}"
    end
  end
end
