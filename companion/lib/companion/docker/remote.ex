defmodule Companion.Docker.Remote do
  @moduledoc """
  Docker adapter that talks to a remote Docker Engine through a Zig
  `telvm-node-agent` HTTP proxy. Each function takes `{base_url, token}` so
  multiple remote engines can be addressed concurrently.

  The Zig agent proxies Docker Engine API calls over its `/docker/*` HTTP
  endpoints. Responses are forwarded as-is (including Docker's multiplexed
  stream format for logs/exec).
  """

  @finch Companion.Finch
  @timeout 30_000

  # ---------------------------------------------------------------------------
  # Read-only queries
  # ---------------------------------------------------------------------------

  def version(base_url, token) do
    get_json(base_url, token, "/docker/version")
  end

  def container_list(base_url, token, opts \\ []) do
    all? = Keyword.get(opts, :all, false)
    path = if all?, do: "/docker/containers?all=true", else: "/docker/containers"

    case get_json(base_url, token, path) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      {:error, _} = e -> e
    end
  end

  def container_inspect(base_url, token, id) do
    case get_json(base_url, token, "/docker/containers/#{enc(id)}/json") do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, {:http, 404, _}} -> {:error, :not_found}
      {:error, _} = e -> e
    end
  end

  def container_stats(base_url, token, id) do
    case get_json(base_url, token, "/docker/containers/#{enc(id)}/stats") do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, {:http, 404, _}} -> {:error, :not_found}
      {:error, _} = e -> e
    end
  end

  def container_logs(base_url, token, id, _opts \\ []) do
    case get_binary(base_url, token, "/docker/containers/#{enc(id)}/logs") do
      {:ok, body} -> {:ok, demux_mixed_stream(body)}
      {:error, _} = e -> e
    end
  end

  # ---------------------------------------------------------------------------
  # Lifecycle mutations (POST, no request body needed by the Zig proxy)
  # ---------------------------------------------------------------------------

  def container_start(base_url, token, id) do
    post_no_body(base_url, token, "/docker/containers/#{enc(id)}/start")
  end

  def container_stop(base_url, token, id) do
    post_no_body(base_url, token, "/docker/containers/#{enc(id)}/stop")
  end

  def container_restart(base_url, token, id) do
    post_no_body(base_url, token, "/docker/containers/#{enc(id)}/restart")
  end

  def container_pause(base_url, token, id) do
    post_no_body(base_url, token, "/docker/containers/#{enc(id)}/pause")
  end

  def container_unpause(base_url, token, id) do
    post_no_body(base_url, token, "/docker/containers/#{enc(id)}/unpause")
  end

  def container_remove(base_url, token, id) do
    delete(base_url, token, "/docker/containers/#{enc(id)}")
  end

  # ---------------------------------------------------------------------------
  # Exec (three-step: create → start → inspect exit code)
  # ---------------------------------------------------------------------------

  def container_exec(base_url, token, container_id, cmd, opts \\ []) when is_list(cmd) do
    workdir = Keyword.get(opts, :workdir)

    exec_body =
      %{"AttachStdout" => true, "AttachStderr" => true, "Cmd" => cmd}
      |> maybe_put("WorkingDir", workdir)
      |> Jason.encode!()

    with {:ok, exec_id} <- create_exec(base_url, token, container_id, exec_body),
         {:ok, raw} <- start_exec(base_url, token, exec_id) do
      {:ok, demux_stdout(raw)}
    end
  end

  def container_exec_with_exit(base_url, token, container_id, cmd, opts \\ [])
      when is_list(cmd) do
    workdir = Keyword.get(opts, :workdir)

    exec_body =
      %{"AttachStdout" => true, "AttachStderr" => true, "Cmd" => cmd}
      |> maybe_put("WorkingDir", workdir)
      |> Jason.encode!()

    with {:ok, exec_id} <- create_exec(base_url, token, container_id, exec_body),
         {:ok, raw} <- start_exec(base_url, token, exec_id),
         {:ok, info} <- inspect_exec(base_url, token, exec_id) do
      exit_code = get_in(info, ["ExitCode"]) || 0
      {:ok, %{stdout: demux_mixed_stream(raw), exit_code: exit_code}}
    end
  end

  # ---------------------------------------------------------------------------
  # Exec helpers
  # ---------------------------------------------------------------------------

  defp create_exec(base_url, token, container_id, body) do
    case post_json(base_url, token, "/docker/containers/#{enc(container_id)}/exec", body) do
      {:ok, %{"Id" => eid}} -> {:ok, eid}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      {:error, _} = e -> e
    end
  end

  defp start_exec(base_url, token, exec_id) do
    body = Jason.encode!(%{"Detach" => false})

    case request(:post, base_url, token, "/docker/exec/#{enc(exec_id)}/start", body) do
      {:ok, %Finch.Response{status: 200, body: raw}} -> {:ok, raw}
      {:ok, %Finch.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, _} = e -> e
    end
  end

  defp inspect_exec(base_url, token, exec_id) do
    get_json(base_url, token, "/docker/exec/#{enc(exec_id)}/json")
  end

  # ---------------------------------------------------------------------------
  # Demux (same logic as Companion.Docker.HTTP)
  # ---------------------------------------------------------------------------

  defp demux_stdout(data), do: demux_stdout(data, [])

  defp demux_stdout(
         <<type, _::binary-size(3), size::32-big, payload::binary-size(size), rest::binary>>,
         acc
       ) do
    if type == 1, do: demux_stdout(rest, [acc, payload]), else: demux_stdout(rest, acc)
  end

  defp demux_stdout(_, acc), do: IO.iodata_to_binary(acc)

  defp demux_mixed_stream(data) when is_binary(data), do: demux_mixed_stream(data, [])

  defp demux_mixed_stream(
         <<type, _::binary-size(3), size::32-big, payload::binary-size(size), rest::binary>>,
         acc
       )
       when type in [1, 2] do
    demux_mixed_stream(rest, [acc, payload])
  end

  defp demux_mixed_stream(<<>>, acc), do: IO.iodata_to_binary(acc)
  defp demux_mixed_stream(trailing, acc) when is_binary(trailing), do: IO.iodata_to_binary([acc, trailing])

  # ---------------------------------------------------------------------------
  # HTTP primitives
  # ---------------------------------------------------------------------------

  defp get_json(base_url, token, path) do
    case request(:get, base_url, token, path) do
      {:ok, %Finch.Response{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %Finch.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, _} = e ->
        e
    end
  end

  defp get_binary(base_url, token, path) do
    case request(:get, base_url, token, path) do
      {:ok, %Finch.Response{status: 200, body: body}} -> {:ok, body}
      {:ok, %Finch.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Finch.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, _} = e -> e
    end
  end

  defp post_no_body(base_url, token, path) do
    case request(:post, base_url, token, path, "{}") do
      {:ok, %Finch.Response{status: s}} when s in [200, 204, 304] -> :ok
      {:ok, %Finch.Response{status: 404}} -> {:error, :not_found}
      {:ok, %Finch.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, _} = e -> e
    end
  end

  defp post_json(base_url, token, path, body) do
    case request(:post, base_url, token, path, body) do
      {:ok, %Finch.Response{status: s, body: resp}} when s in [200, 201] ->
        case Jason.decode(resp) do
          {:ok, decoded} -> {:ok, decoded}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %Finch.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}

      {:error, _} = e ->
        e
    end
  end

  defp delete(base_url, token, path) do
    case request(:delete, base_url, token, path) do
      {:ok, %Finch.Response{status: s}} when s in [200, 204] -> :ok
      {:ok, %Finch.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, _} = e -> e
    end
  end

  defp request(method, base_url, token, path, body \\ "") do
    url = String.trim_trailing(base_url, "/") <> path

    headers =
      [{"host", "localhost"}] ++
        if(token != "", do: [{"authorization", "Bearer #{token}"}], else: []) ++
        if(body != "", do: [{"content-type", "application/json"}], else: [])

    Finch.build(method, url, headers, body)
    |> Finch.request(@finch, receive_timeout: @timeout)
  end

  defp enc(id), do: URI.encode(id, &URI.char_unreserved?/1)

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)
end
