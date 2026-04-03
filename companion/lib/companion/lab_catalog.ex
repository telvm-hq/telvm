defmodule Companion.LabCatalog do
  @moduledoc false

  # JSON on GET / — predictable for humans, agents, and proxy smoke tests (not HTML dir listings).
  # Repo `images/go-http-lab/` is Docker build context only, not Phoenix static assets.

  @bun_cmd [
    "bun",
    "-e",
    "Bun.serve({ port: 3333, fetch() { return new Response(JSON.stringify({status:'ok',service:'telvm-lab',probe:'/'}), { headers: { 'Content-Type': 'application/json' } }); } })"
  ]

  @go_src Enum.join(
            [
              "package main",
              "",
              "import (",
              "\t\"encoding/json\"",
              "\t\"net/http\"",
              ")",
              "",
              "func main() {",
              "\thttp.HandleFunc(\"/\", func(w http.ResponseWriter, r *http.Request) {",
              "\t\tw.Header().Set(\"Content-Type\", \"application/json\")",
              "\t\t_ = json.NewEncoder(w).Encode(map[string]string{\"status\": \"ok\", \"service\": \"telvm-lab\", \"probe\": \"/\"})",
              "\t})",
              "\t_ = http.ListenAndServe(\"0.0.0.0:3333\", nil)",
              "}"
            ],
            "\n"
          )

  @go_cmd [
    "sh",
    "-c",
    "cat > /tmp/telvm.go << 'EOF'\n" <> @go_src <> "\nEOF\ncd /tmp && go run telvm.go\n"
  ]

  # Stdlib only: raw HTTP/1.1 response on :gen_tcp (no Mix, no deps).
  @elixir_exs ~S"""
  {:ok, l} =
    :gen_tcp.listen(3333, [
      :binary,
      {:packet, :raw},
      {:active, false},
      {:reuseaddr, true},
      {:ip, {0, 0, 0, 0}}
    ])

  f = fn me ->
    {:ok, c} = :gen_tcp.accept(l)
    {:ok, _} = :gen_tcp.recv(c, 2048)
    body = ~s({"status":"ok","service":"telvm-lab","probe":"/"})

    resp =
      "HTTP/1.1 200 OK" <>
        <<13, 10>> <>
        "Content-Type: application/json" <>
        <<13, 10>> <>
        "Content-Length: #{byte_size(body)}" <>
        <<13, 10>> <>
        <<13, 10>> <>
        body

    :ok = :gen_tcp.send(c, resp)
    :ok = :gen_tcp.close(c)
    me.(me)
  end

  f.(f)
  """

  @elixir_cmd [
    "sh",
    "-c",
    "cat > /tmp/telvm_lab.exs << 'EOF'\n" <>
      @elixir_exs <> "\nEOF\nexec elixir /tmp/telvm_lab.exs\n"
  ]

  @python_uv_src Enum.join(
                   [
                     "from starlette.applications import Starlette",
                     "from starlette.responses import JSONResponse",
                     "from starlette.routing import Route",
                     "async def homepage(request):",
                     "    return JSONResponse({\"status\": \"ok\", \"service\": \"telvm-lab\", \"probe\": \"/\"})",
                     "app = Starlette(routes=[Route(\"/\", homepage)])",
                     "import uvicorn",
                     "uvicorn.run(app, host=\"0.0.0.0\", port=3333)"
                   ],
                   "\n"
                 )

  @python_uvicorn_cmd [
    "sh",
    "-c",
    "pip install -q --disable-pip-version-check uvicorn starlette && python << 'PY'\n" <>
      @python_uv_src <> "\nPY\n"
  ]

  @c_src Enum.join(
           [
             "#include <stdio.h>",
             "#include <string.h>",
             "#include <unistd.h>",
             "#include <sys/socket.h>",
             "#include <netinet/in.h>",
             "#include <arpa/inet.h>",
             "",
             "int main(void) {",
             "  int s = socket(AF_INET, SOCK_STREAM, 0);",
             "  int opt = 1;",
             "  setsockopt(s, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));",
             "  struct sockaddr_in a;",
             "  memset(&a, 0, sizeof(a));",
             "  a.sin_family = AF_INET;",
             "  a.sin_port = htons(3333);",
             "  a.sin_addr.s_addr = htonl(INADDR_ANY);",
             "  bind(s, (struct sockaddr *)&a, sizeof(a));",
             "  listen(s, 8);",
             "  const char *j = \"{\\\"status\\\":\\\"ok\\\",\\\"service\\\":\\\"telvm-lab\\\",\\\"probe\\\":\\\"/\\\"}\";",
             "  char resp[512];",
             "  int n = snprintf(resp, sizeof(resp),",
             "    \"HTTP/1.1 200 OK\\r\\nContent-Type: application/json\\r\\nContent-Length: %zu\\r\\n\\r\\n%s\",",
             "    strlen(j), j);",
             "  for (;;) {",
             "    int fd = accept(s, NULL, NULL);",
             "    char tmp[2048];",
             "    (void)read(fd, tmp, sizeof(tmp));",
             "    (void)write(fd, resp, n);",
             "    close(fd);",
             "  }",
             "}"
           ],
           "\n"
         )

  @c_cmd [
    "sh",
    "-c",
    "cat > /tmp/telvm.c << 'EOF'\n" <>
      @c_src <> "\nEOF\ngcc -o /tmp/telvm_http /tmp/telvm.c && exec /tmp/telvm_http\n"
  ]

  @hub_catalog [
    %{
      id: :lab_bun,
      label: "Node + Bun",
      icon: "hero-bolt",
      ref: "oven/bun:1-alpine",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @bun_cmd,
      source: :hub,
      build_context: nil,
      telvm_certified: false,
      container_env: []
    },
    %{
      id: :lab_go,
      label: "Go",
      icon: "hero-bolt",
      ref: "golang:1.23-alpine",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @go_cmd,
      source: :hub,
      build_context: nil,
      telvm_certified: false,
      container_env: []
    },
    %{
      id: :lab_elixir,
      label: "Elixir + mix",
      icon: "hero-sparkles",
      ref: "elixir:1.18-alpine",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @elixir_cmd,
      source: :hub,
      build_context: nil,
      telvm_certified: false,
      container_env: []
    },
    %{
      id: :lab_python_uv,
      label: "python + uv",
      icon: "hero-command-line",
      ref: "python:3.12-slim-bookworm",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @python_uvicorn_cmd,
      source: :hub,
      build_context: nil,
      telvm_certified: false,
      container_env: []
    },
    %{
      id: :lab_c,
      label: "C + gcc",
      icon: "hero-code-bracket",
      ref: "gcc:14-bookworm",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @c_cmd,
      source: :hub,
      build_context: nil,
      telvm_certified: false,
      container_env: []
    }
  ]

  @doc """
  Published certified stacks (`ghcr.io/<owner>/telvm-lab-*:main`). Override owner with
  `TELVM_LAB_GHCR_ORG` (default `telvm-hq`) so local pulls match your registry.
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
        container_env: []
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
        container_env: []
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
        container_env: []
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
        container_env: []
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
        container_env: []
      }
    ]
  end

  def entries, do: certified_entries() ++ @hub_catalog

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
