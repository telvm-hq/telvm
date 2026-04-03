defmodule Companion.LabCatalog do
  @moduledoc false

  # Certified GHCR stacks only. Other images: paste a ref in the BYOI field on Machines.

  @doc """
  Published certified stacks (`ghcr.io/<owner>/telvm-lab-*:main`). Override owner with
  `TELVM_LAB_GHCR_ORG` (default `telvm-hq`) so local pulls match your registry.

  Each entry includes `stack_disclosure` (what is installed; plain text for humans and agents)
  and `best_practice` (why this shape matches common production guidance).
  """
  def certified_entries do
    org =
      case System.get_env("TELVM_LAB_GHCR_ORG") do
        nil -> "telvm-hq"
        "" -> "telvm-hq"
        o -> o |> String.trim() |> String.downcase()
      end

    prefix = "ghcr.io/#{org}/telvm-lab-"

    [
      %{
        id: :cert_phoenix,
        label: "Phoenix (certified)",
        icon: "hero-sparkles",
        ref: "#{prefix}phoenix:main",
        probe_port: 3333,
        use_image_cmd: true,
        container_cmd: nil,
        source: :ghcr,
        build_context: nil,
        telvm_certified: true,
        container_env: [],
        stack_card: "elixir_stack.png",
        stack_disclosure: """
        image: telvm-lab-phoenix (multi-stage)
        build_base: hexpm/elixir:1.18.2-erlang-27.2-alpine-3.21.2
        runtime_base: alpine:3.21
        language: Elixir 1.18.x on Erlang/OTP 27.2
        web: Phoenix (HTTP via Bandit adapter in release)
        build_tool: Mix (deps.get prod, mix release)
        artifact: single OTP release under /app (telvm_lab)
        runtime_libs: libstdc++, openssl, ncurses-libs (Alpine)
        user: non-root labuser uid 10001
        listen: 0.0.0.0:3333
        probe: GET / -> JSON (status, service, probe)
        """,
        best_practice: """
        Uses an OTP release instead of `mix phx.server` in the container: smaller surface, \
        explicit prod config, and the same packaging model as production Elixir deploys. \
        Running as a non-root user and a slim Alpine runtime matches common hardening guidance.
        """
      },
      %{
        id: :cert_go,
        label: "Go (certified)",
        icon: "hero-bolt",
        ref: "#{prefix}go:main",
        probe_port: 3333,
        use_image_cmd: true,
        container_cmd: nil,
        source: :ghcr,
        build_context: nil,
        telvm_certified: true,
        container_env: [],
        stack_card: "go_stack.png",
        stack_disclosure: """
        image: telvm-lab-go (multi-stage)
        build_base: golang:1.23-alpine
        runtime_base: alpine:3.21
        language: Go 1.23
        router: github.com/gofiber/fiber/v2 v2.52.5
        link: static binary CGO_ENABLED=0, -ldflags -s -w
        binary: /lab (single file)
        user: non-root labuser uid 10001
        listen: 0.0.0.0:3333
        probe: GET / -> JSON
        """,
        best_practice: """
        Statically linked Go binary on minimal Alpine is a standard pattern: one artifact, no \
        toolchain in runtime, fast cold starts. Fiber is a common high-throughput HTTP router; \
        non-root execution limits container blast radius.
        """
      },
      %{
        id: :cert_python,
        label: "Python (certified)",
        icon: "hero-command-line",
        ref: "#{prefix}python:main",
        probe_port: 3333,
        use_image_cmd: true,
        container_cmd: nil,
        source: :ghcr,
        build_context: nil,
        telvm_certified: true,
        container_env: [],
        stack_card: "python_stack.png",
        stack_disclosure: """
        image: telvm-lab-python (single-stage)
        base: python:3.12-slim-bookworm
        language: Python 3.12
        framework: FastAPI 0.115.6
        server: uvicorn[standard] 0.34.0 (ASGI)
        app: main:app (see images/telvm-lab-python/main.py)
        user: non-root labuser uid 10001
        listen: 0.0.0.0:3333
        probe: GET / -> JSON
        """,
        best_practice: """
        FastAPI with an explicit ASGI server (uvicorn) matches mainstream Python API practice: \
        typed routes, OpenAPI-friendly, and a clear separation between app code and the \
        process supervisor. Slim Bookworm reduces image size versus full Debian while staying \
        glibc-compatible for many wheels.
        """
      },
      %{
        id: :cert_erlang,
        label: "Erlang (certified)",
        icon: "hero-bolt",
        ref: "#{prefix}erlang:main",
        probe_port: 3333,
        use_image_cmd: true,
        container_cmd: nil,
        source: :ghcr,
        build_context: nil,
        telvm_certified: true,
        container_env: [],
        stack_card: "erlang_stack.png",
        stack_disclosure: """
        image: telvm-lab-erlang (single-stage build + release)
        base: erlang:27-alpine
        language: Erlang/OTP 27
        build_tool: rebar3 3.24.0 (downloaded in image)
        http: Cowboy 2.12.0 (dependency)
        artifact: rebar3 release telvm_lab (extended start script)
        user: non-root labuser uid 10001
        workdir: release root (_build/default/rel/telvm_lab)
        listen: Cowboy on 0.0.0.0:3333
        probe: GET / -> JSON
        """,
        best_practice: """
        A rebar3 release is the idiomatic way to ship Erlang: OTP applications, supervision \
        trees, and Cowboy as the embedded HTTP listener—same shape as long-running BEAM services. \
        Non-root and a minimal Alpine+Erlang base align with typical container Erlang deploys.
        """
      },
      %{
        id: :cert_c,
        label: "C (certified)",
        icon: "hero-code-bracket",
        ref: "#{prefix}c:main",
        probe_port: 3333,
        use_image_cmd: true,
        container_cmd: nil,
        source: :ghcr,
        build_context: nil,
        telvm_certified: true,
        container_env: [],
        stack_card: "c_stack.png",
        stack_disclosure: """
        image: telvm-lab-c (multi-stage)
        build_base: alpine:3.21 + gcc musl-dev libmicrohttpd-dev
        runtime_base: alpine:3.21 + libmicrohttpd (shared lib)
        language: C (musl)
        http: GNU libmicrohttpd embedded server
        binary: /lab (compiled from main.c)
        user: non-root labuser uid 10001
        listen: 0.0.0.0:3333
        probe: GET / -> JSON
        """,
        best_practice: """
        Multi-stage build keeps only the runtime libs and binary—no compiler in the final \
        layer. libmicrohttpd is a small, common choice for minimal C HTTP services; non-root \
        and Alpine musl match typical minimal-container C workloads.
        """
      }
    ]
  end

  def entries, do: certified_entries()

  def get(id) when is_atom(id) do
    Enum.find(entries(), &(&1.id == id))
  end

  @doc """
  Annotate catalog entries with `:available` boolean by matching each `ref`
  against `RepoTags` from `Docker.impl().image_list([])`.
  """
  def with_availability(entries \\ :all)

  def with_availability(:all), do: with_availability(entries())

  def with_availability(entries) when is_list(entries) do
    local_tags =
      case Companion.Docker.impl().image_list([]) do
        {:ok, images} ->
          images
          |> Enum.flat_map(fn img -> Map.get(img, "RepoTags", []) || [] end)
          |> MapSet.new()

        {:error, _} ->
          MapSet.new()
      end

    Enum.map(entries, fn entry ->
      Map.put(entry, :available, MapSet.member?(local_tags, entry.ref))
    end)
  end
end
