defmodule CompanionWeb.ProxyPlug do
  @default_port 3000

  @moduledoc """
  Intercepts `/app/*` before the router and proxies to sandbox containers via Finch.

  URL shape: `/app/<container_name>/port/<port_number>/[path…][?query]`

  The `container_name` segment is the Docker bridge DNS hostname of the target
  container (e.g. `telvm-vm-mgr-39779`). Companion and lab containers share a
  bridge network, so Docker DNS resolves the name to the container IP.

  The `port/<n>` segment is optional. Without it the default port #{@default_port}
  is used. The `/port/` prefix avoids colons in path segments, which
  `Plug.Static` rejects as invalid characters.

  HTTP forwarding is performed by `Companion.Finch`. The response (headers + body +
  status) is streamed back to the browser as-is, with hop-by-hop headers stripped.
  Returns 502 when the upstream container is unreachable.
  """

  import Plug.Conn
  @behaviour Plug

  # Hop-by-hop headers must not be forwarded.
  @strip_req_headers ~w(host transfer-encoding content-length connection keep-alive
                        proxy-authenticate proxy-authorization te trailers upgrade)
  @strip_resp_headers ~w(transfer-encoding connection keep-alive
                         proxy-authenticate proxy-authorization te trailers upgrade)

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    case parse_app_path(conn.path_info) do
      {:ok, %{session_id: sid, port: port, path_segments: segs}} ->
        forward(conn, sid, port, segs)

      :error ->
        conn
    end
  end

  defp forward(conn, sid, port, path_segments) do
    path = "/" <> Enum.join(path_segments, "/")
    qs = if conn.query_string != "", do: "?" <> conn.query_string, else: ""
    upstream = "http://#{sid}:#{port}#{path}#{qs}"

    headers =
      Enum.reject(conn.req_headers, fn {k, _} -> k in @strip_req_headers end)

    {:ok, body, conn} = Plug.Conn.read_body(conn)
    method = conn.method |> String.downcase() |> String.to_atom()

    http_fun = Application.get_env(:companion, :proxy_http_fun)

    result =
      if is_function(http_fun, 4) do
        http_fun.(method, upstream, headers, body)
      else
        req = Finch.build(method, upstream, headers, body)
        Finch.request(req, Companion.Finch)
      end

    case result do
      {:ok, resp} ->
        resp_headers =
          Enum.reject(resp.headers, fn {k, _} -> k in @strip_resp_headers end)

        conn
        |> merge_resp_headers(resp_headers)
        |> send_resp(resp.status, resp.body)
        |> halt()

      {:error, _reason} ->
        conn
        |> put_resp_content_type("text/plain")
        |> send_resp(502, "Container unreachable via bridge DNS (#{sid}:#{port}).\n")
        |> halt()
    end
  end

  @doc """
  Parses `conn.path_info` for `/app/<session_id>/port/<port_number>/...`.

  - No explicit `port/<n>` segment → `#{@default_port}` and all remaining path segments.
  - `["port", digits | rest]` where digits is a valid port number → that port + rest.
  """
  def parse_app_path(["app", session_id | rest]) when session_id != "" do
    {port, path_segments} = take_port(rest)
    {:ok, %{session_id: session_id, port: port, path_segments: path_segments}}
  end

  def parse_app_path(_), do: :error

  defp take_port(["port", digits | path]) do
    case Integer.parse(digits) do
      {n, ""} when n > 0 and n < 65536 -> {n, path}
      _ -> {@default_port, ["port", digits | path]}
    end
  end

  defp take_port(segments), do: {@default_port, segments}
end
