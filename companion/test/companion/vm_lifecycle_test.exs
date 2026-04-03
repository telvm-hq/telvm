defmodule Companion.VmLifecycleTest do
  use ExUnit.Case, async: false

  alias Companion.VmLifecycle

  setup do
    System.delete_env("TELVM_LAB_USE_IMAGE_CMD")

    on_exit(fn ->
      System.delete_env("TELVM_LAB_USE_IMAGE_CMD")
    end)

    :ok
  end

  describe "lab_container_create_attrs/2" do
    test "includes default Node Cmd when use_image_default_cmd is off" do
      cfg = VmLifecycle.manager_preflight_config()
      attrs = VmLifecycle.lab_container_create_attrs(cfg, "telvm-test-1")

      assert %{"Cmd" => ["node", "-e", _]} = attrs
      assert attrs["Image"] == "node:22-alpine"
    end

    test "omits Cmd when TELVM_LAB_USE_IMAGE_CMD is truthy" do
      System.put_env("TELVM_LAB_USE_IMAGE_CMD", "1")
      cfg = VmLifecycle.manager_preflight_config()
      attrs = VmLifecycle.lab_container_create_attrs(cfg, "telvm-test-2")

      refute Map.has_key?(attrs, "Cmd")
      assert attrs["Image"] == "node:22-alpine"
    end

    test "includes Env when container_env is set" do
      cfg =
        VmLifecycle.manager_preflight_config(
          image: "ghcr.io/example/lab:main",
          use_image_default_cmd: true,
          container_env: [{"FOO", "bar"}, {"BAZ", "1"}]
        )

      attrs = VmLifecycle.lab_container_create_attrs(cfg, "telvm-env-1")
      assert attrs["Env"] == ["FOO=bar", "BAZ=1"]
    end
  end

  describe "manager_preflight_config/1 merge" do
    test "overrides win over base for image and use_image_default_cmd" do
      cfg =
        VmLifecycle.manager_preflight_config(
          image: "ghcr.io/example/telvm-go-http-lab:main",
          use_image_default_cmd: true
        )

      assert cfg[:image] == "ghcr.io/example/telvm-go-http-lab:main"
      assert cfg[:use_image_default_cmd] == true
    end

    test "empty overrides match base-only config" do
      assert VmLifecycle.manager_preflight_config([]) == VmLifecycle.manager_preflight_config()
    end
  end
end
