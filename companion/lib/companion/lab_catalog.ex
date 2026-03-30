defmodule Companion.LabCatalog do
  @moduledoc false

  # JSON on GET / — predictable for humans, agents, and proxy smoke tests (not HTML dir listings).
  @node_cmd [
    "node",
    "-e",
    "require('http').createServer((q,r)=>{r.setHeader('Content-Type','application/json');r.end(JSON.stringify({status:'ok',service:'telvm-lab',probe:'/'}))}).listen(3333,'0.0.0.0')"
  ]

  @python_cmd [
    "python3",
    "-c",
    "import json\nfrom http.server import HTTPServer, BaseHTTPRequestHandler\nclass H(BaseHTTPRequestHandler):\n    def do_GET(self):\n        self.send_response(200)\n        self.send_header('Content-Type', 'application/json')\n        self.end_headers()\n        self.wfile.write(json.dumps({'status': 'ok', 'service': 'telvm-lab', 'probe': '/'}).encode())\nHTTPServer(('0.0.0.0', 3333), H).serve_forever()"
  ]

  @ruby_cmd ["ruby", "-run", "-ehttpd", "/tmp", "-p3333"]

  @busybox_cmd ["sh", "-c", "echo ok > /tmp/index.html && httpd -f -p 3333 -h /tmp"]

  @catalog [
    %{
      id: :stock_node,
      label: "Stock Node",
      ref: "node:22-alpine",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @node_cmd,
      source: :hub,
      build_context: nil
    },
    %{
      id: :go_http_lab,
      label: "Go HTTP lab",
      ref: "telvm-go-http-lab:local",
      probe_port: 3333,
      use_image_cmd: true,
      container_cmd: nil,
      source: :local_build,
      build_context: "/images/go-http-lab"
    },
    %{
      id: :python_http,
      label: "Python HTTP",
      ref: "python:3.12-alpine",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @python_cmd,
      source: :hub,
      build_context: nil
    },
    %{
      id: :ruby_http,
      label: "Ruby HTTP",
      ref: "ruby:3.3-alpine",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @ruby_cmd,
      source: :hub,
      build_context: nil
    },
    %{
      id: :busybox_http,
      label: "BusyBox HTTP",
      ref: "busybox:latest",
      probe_port: 3333,
      use_image_cmd: false,
      container_cmd: @busybox_cmd,
      source: :hub,
      build_context: nil
    }
  ]

  def entries, do: @catalog

  def get(id) when is_atom(id) do
    Enum.find(@catalog, &(&1.id == id))
  end

  @doc """
  Annotate catalog entries with `:available` boolean by matching each `ref`
  against `RepoTags` from `Docker.impl().image_list([])`.
  """
  def with_availability(entries \\ @catalog) do
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

