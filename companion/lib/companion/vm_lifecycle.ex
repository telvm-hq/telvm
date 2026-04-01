defmodule Companion.VmLifecycle do
  @moduledoc false

  @topic "lifecycle:vm_manager_preflight"

  def topic, do: @topic

  @doc """
  Body map for `POST /containers/create` (plus `"Name"` popped by the HTTP client).

  When `use_image_default_cmd` is true (via `TELVM_LAB_USE_IMAGE_CMD=1` or application config),
  `"Cmd"` is omitted so Engine uses the image `CMD`/`ENTRYPOINT`—required for registry-backed
  lab images that embed their own command.
  """
  def lab_container_create_attrs(cfg, name) when is_list(cfg) and is_binary(name) do
    port = cfg[:exposed_port]
    pkey = "#{port}/tcp"
    net = cfg[:docker_network]
    dns_alias = cfg[:dns_alias]

    binds =
      case cfg[:workspace] do
        nil -> []
        "" -> []
        path -> ["#{path}:/workspace:rw"]
      end

    base = %{
      "Name" => name,
      "Image" => cfg[:image],
      "Labels" => %{"telvm.vm_manager_lab" => "true"},
      "ExposedPorts" => %{pkey => %{}},
      "HostConfig" => %{
        "NetworkMode" => net,
        "Binds" => binds
      },
      "NetworkingConfig" => %{
        "EndpointsConfig" => %{
          net => %{"Aliases" => [dns_alias]}
        }
      }
    }

    if Keyword.get(cfg, :use_image_default_cmd, false) do
      base
    else
      Map.put(base, "Cmd", cfg[:container_cmd])
    end
  end

  @doc """
  Base config from defaults, application env, and `TELVM_LAB_*` / `TELVM_LAB_USE_IMAGE_CMD`,
  then merged with `overrides` (later keys win). Use `[]` for stock behavior.
  """
  def manager_preflight_config(overrides \\ []) when is_list(overrides) do
    Keyword.merge(manager_preflight_config_base(), overrides)
  end

  defp manager_preflight_config_base do
    defaults = [
      docker_network: "telvm_default",
      dns_alias: "telvm-lab-workload",
      image: "node:22-alpine",
      exposed_port: 3333,
      use_image_default_cmd: false,
      container_cmd: [
        "node",
        "-e",
        "require('http').createServer((q,r)=>{r.setHeader('Content-Type','application/json');r.end(JSON.stringify({status:'ok',service:'telvm-lab',probe:'/'}))}).listen(3333,'0.0.0.0')"
      ],
      health_window_ms: 5_000,
      health_probe_interval_ms: 400,
      http_probe_path: "/",
      stop_timeout_sec: 10,
      wait_running_timeout_ms: 45_000
    ]

    legacy = Application.get_env(:companion, :vm_certificate, [])
    modern = Application.get_env(:companion, :vm_manager_preflight, [])
    merged = defaults |> Keyword.merge(legacy) |> Keyword.merge(modern)

    merged
    |> maybe_put_env_string("TELVM_LAB_DOCKER_NETWORK", :docker_network)
    |> maybe_put_env_string("TELVM_LAB_DNS_ALIAS", :dns_alias)
    |> maybe_put_env_string("TELVM_LAB_IMAGE", :image)
    |> maybe_put_env_int("TELVM_LAB_EXPOSED_PORT", :exposed_port)
    |> maybe_put_use_image_cmd_from_env()
  end

  defp maybe_put_env_string(kw, var, key) do
    case System.get_env(var) do
      nil -> kw
      "" -> kw
      v -> Keyword.put(kw, key, v)
    end
  end

  defp maybe_put_env_int(kw, var, key) do
    case System.get_env(var) do
      nil ->
        kw

      v ->
        case Integer.parse(v) do
          {n, _} -> Keyword.put(kw, key, n)
          :error -> kw
        end
    end
  end

  defp maybe_put_use_image_cmd_from_env(kw) do
    if env_truthy?("TELVM_LAB_USE_IMAGE_CMD") do
      Keyword.put(kw, :use_image_default_cmd, true)
    else
      kw
    end
  end

  defp env_truthy?(var) do
    case System.get_env(var) do
      nil ->
        false

      "" ->
        false

      v ->
        v = v |> String.trim() |> String.downcase()
        v in ["1", "true", "yes"]
    end
  end
end
