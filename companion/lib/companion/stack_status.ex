defmodule Companion.StackStatus do
  @moduledoc false

  alias Companion.Repo

  @doc "ASCII diagram for the status page (Windows host → Compose)."
  def host_diagram_string do
    """
      [ Browser — Windows ]
             |
             |  http://localhost:4000/
             v
    +---------------------------+
    |  Docker Desktop           |
    |  publish 4000:4000        |
    +---------------------------+
             |
             v
    +---------------------------+
    |  container: companion      |
    |  Phoenix + Bandit + LV     |
    +---------------------------+
             |  |  |
             |  |  +-- docker.sock -> Engine API (Finch)
             |  |
             |  +----- Ecto Repo -> db:5432
             |
             +-------- vm_node hostname -> :3333 (example VM)
             |
             v
    +---------------------------+     +---------------------------+
    |  container: db             |     |  container: vm_node     |
    |  Postgres                  |     |  Node + telvm labels    |
    +---------------------------+     +---------------------------+
    """
    |> String.trim_trailing()
  end

  @doc """
  Runs `SELECT 1` through the app Repo. Returns `{:ok, latency_ms}` or `{:error, message}`.
  """
  def postgres do
    t0 = System.monotonic_time(:millisecond)

    case Ecto.Adapters.SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} ->
        {:ok, System.monotonic_time(:millisecond) - t0}

      {:error, %DBConnection.ConnectionError{} = e} ->
        {:error, Exception.message(e)}

      {:error, %Postgrex.Error{} = e} ->
        {:error, Exception.message(e)}

      {:error, e} ->
        {:error, inspect(e)}
    end
  end

  @doc "True if the Engine socket is present inside this environment (e.g. Compose mount)."
  def docker_socket? do
    File.exists?("/var/run/docker.sock")
  end

  @doc "Human-readable Docker adapter module (behaviour implementation)."
  def docker_adapter_label do
    Companion.Docker.impl() |> Module.split() |> Enum.join(".")
  end

  @doc """
  Static description of what `docker compose up` runs by default (two services).
  """
  def compose_stack_rows do
    [
      %{
        name: "db (Postgres 16)",
        role: "Compose service `db`",
        note: "Stores app data; reachable as hostname `db` on the Compose network."
      },
      %{
        name: "vm_node (Node 22)",
        role: "Compose service `vm_node`",
        note:
          "Example companion workload: `node:22-alpine` with labels `telvm.sandbox=true`, `telvm.runtime=node`; tiny HTTP on :3333 for future probes."
      },
      %{
        name: "companion (Phoenix)",
        role: "Compose service `companion`",
        note:
          "Dashboard + Docker Engine client. Asset toolchain (Node) runs inside this image. Named volume holds `assets/node_modules`."
      },
      %{
        name: "companion_test",
        role: "Profile `test` only",
        note: "One-shot `mix test`; not started by plain `docker compose up`."
      }
    ]
  end
end
