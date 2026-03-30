defmodule Companion.Preflight do
  @moduledoc false

  alias Companion.StackStatus

  @pubsub_topic "preflight:updates"

  @doc false
  def topic, do: @pubsub_topic

  @doc """
  Runs all checks and returns a report suitable for LiveView and PubSub broadcast.
  """
  def run do
    adapter = Companion.Docker.impl()
    checks = checks(adapter)

    %{
      checks: checks,
      rollup: compute_rollup(checks),
      refreshed_at: DateTime.utc_now()
    }
  end

  @doc false
  def compute_rollup(checks) when is_list(checks), do: rollup(checks)

  @doc """
  Builds the `filters` map for `GET /containers/json` (Docker Engine API).
  """
  def vm_node_filters do
    %{
      "label" => ["telvm.sandbox=true"],
      "status" => ["running"]
    }
  end

  defp checks(adapter) do
    [
      postgres_check(),
      docker_socket_check(),
      adapter_check(adapter),
      engine_check(adapter),
      companion_vm_check(adapter),
      proxy_plug_check(),
      informational_rows()
    ]
    |> List.flatten()
  end

  defp postgres_check do
    case StackStatus.postgres() do
      {:ok, ms} ->
        check(:postgres, :gating, :pass, "Postgres (Ecto Repo)", "SELECT 1 round-trip #{ms} ms")

      {:error, msg} ->
        check(:postgres, :gating, :fail, "Postgres (Ecto Repo)", msg)
    end
  end

  defp docker_socket_check do
    if StackStatus.docker_socket?() do
      check(
        :docker_socket,
        :gating,
        :pass,
        "Docker socket",
        "/var/run/docker.sock present (Engine API reachable when adapter is HTTP)"
      )
    else
      check(
        :docker_socket,
        :gating,
        :warn,
        "Docker socket",
        "Socket not mounted; use docker compose or mount /var/run/docker.sock for Engine checks"
      )
    end
  end

  defp adapter_check(adapter) do
    check(
      :docker_adapter,
      :info,
      :info,
      "Docker behaviour adapter",
      module_label(adapter)
    )
  end

  defp engine_check(Companion.Docker.Mock) do
    check(
      :docker_engine,
      :gating,
      :skip,
      "Docker Engine API (Finch + Unix socket)",
      "Skipped: Mock adapter active (tests or no socket / no HTTP adapter configured)"
    )
  end

  defp engine_check(adapter) do
    case adapter.version() do
      {:ok, %{"Version" => v}} ->
        check(
          :docker_engine,
          :gating,
          :pass,
          "Docker Engine API (Finch + Unix socket)",
          "GET /version OK — Engine #{v}"
        )

      {:ok, map} when is_map(map) ->
        check(
          :docker_engine,
          :gating,
          :pass,
          "Docker Engine API (Finch + Unix socket)",
          "GET /version OK — #{inspect(Map.take(map, ["Version", "ApiVersion"]))}"
        )

      {:error, reason} ->
        check(
          :docker_engine,
          :gating,
          :fail,
          "Docker Engine API (Finch + Unix socket)",
          "Call failed: #{format_error(reason)}"
        )
    end
  end

  defp companion_vm_check(Companion.Docker.Mock) do
    check(
      :companion_vm,
      :gating,
      :skip,
      "Labeled companion VM (telvm.sandbox)",
      "Skipped with Mock adapter"
    )
  end

  defp companion_vm_check(adapter) do
    case adapter.container_list(filters: vm_node_filters()) do
      {:ok, []} ->
        check(
          :companion_vm,
          :gating,
          :warn,
          "Labeled companion VM (telvm.sandbox)",
          "No running containers with label telvm.sandbox=true (start stack with vm_node service)"
        )

      {:ok, list} when is_list(list) ->
        names =
          list
          |> Enum.map(&container_display_name/1)
          |> Enum.join(", ")

        check(
          :companion_vm,
          :gating,
          :pass,
          "Labeled companion VM (telvm.sandbox)",
          "#{length(list)} running — #{names}"
        )

      {:error, reason} ->
        check(
          :companion_vm,
          :gating,
          :warn,
          "Labeled companion VM (telvm.sandbox)",
          "List failed: #{format_error(reason)}"
        )
    end
  end

  defp container_display_name(%{"Names" => [name | _]}) when is_binary(name), do: name
  defp container_display_name(%{"Id" => id}) when is_binary(id), do: String.slice(id, 0, 12)
  defp container_display_name(_), do: "?"

  defp proxy_plug_check do
    check(
      :proxy_plug,
      :info,
      :pass,
      "ProxyPlug /app/… contract",
      "Finch upstream active — /app/<container>/:port/ proxies to container bridge DNS"
    )
  end

  defp informational_rows do
    [
      check(
        :roadmap_http_surface,
        :info,
        :info,
        "Docker HTTP adapter surface",
        "Pre-flight uses version + container list; create/exec/stats/stream not implemented yet"
      ),
      check(
        :roadmap_health,
        :info,
        :info,
        "HealthMonitor + PubSub vitals",
        "Not wired — pre-flight uses Companion.PreflightServer + \"#{@pubsub_topic}\""
      ),
      check(
        :roadmap_catalog,
        :info,
        :info,
        "Runtime image catalog",
        "Roadmap: 5 core images in v0.1.0; 21+ profiles later (see internal roadmap)"
      ),
      check(
        :roadmap_zig,
        :info,
        :info,
        "telvm-agent (Zig)",
        "Not in v0.1.0 — BYOI via Engine API only"
      )
    ]
  end

  defp check(id, kind, status, title, detail) do
    %{id: id, kind: kind, status: status, title: title, detail: detail}
  end

  defp rollup(checks) do
    gating = Enum.filter(checks, &(&1.kind == :gating))

    cond do
      Enum.any?(gating, &(&1.status == :fail)) ->
        :blocked

      Enum.all?(gating, &(&1.status == :pass)) ->
        :ready

      true ->
        :degraded
    end
  end

  defp format_error({:http, status, body}) when is_binary(body) do
    "HTTP #{status}: #{String.slice(body, 0, 200)}"
  end

  defp format_error({:http, status, body}) do
    "HTTP #{status}: #{inspect(body)}"
  end

  defp format_error(other), do: inspect(other)

  defp module_label(mod), do: mod |> Module.split() |> Enum.join(".")
end
