defmodule Companion.Docker.HTTP do
  @moduledoc false

  @behaviour Companion.Docker

  @finch Companion.Finch

  @impl true
  def version do
    case get_json(path("version")) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, _} = e -> e
    end
  end

  @impl true
  def container_list(opts) do
    filters = Keyword.get(opts, :filters)

    path =
      case filters do
        nil ->
          path("containers/json")

        map when map == %{} ->
          path("containers/json")

        map when is_map(map) ->
          q = URI.encode_query(%{"filters" => Jason.encode!(map)})
          path("containers/json") <> "?" <> q
      end

    case get_json(path) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      {:error, _} = e -> e
    end
  end

  @impl true
  def container_inspect(id) do
    case get_json(path("containers/#{enc_id(id)}/json")) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, {:http, 404, _}} -> {:error, :not_found}
      {:error, _} = e -> e
    end
  end

  @impl true
  def container_create(attrs) when is_map(attrs) do
    {name, body_map} = Map.pop(attrs, "Name")
    q = if name, do: "?" <> URI.encode_query(%{"name" => name}), else: ""
    body = Jason.encode!(body_map)

    case request(:post, path("containers/create") <> q, body, "application/json") do
      {:ok, %Finch.Response{status: status, body: resp}} when status in [200, 201] ->
        case Jason.decode(resp) do
          {:ok, %{"Id" => cid}} -> {:ok, cid}
          {:ok, other} -> {:error, {:unexpected_body, other}}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %Finch.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}

      {:error, _} = e ->
        e
    end
  end

  @impl true
  def container_start(id, _opts) do
    post_no_body(path("containers/#{enc_id(id)}/start"))
  end

  @impl true
  def container_stop(id, opts) do
    t = Keyword.get(opts, :timeout_sec, 10)
    q = URI.encode_query(%{"t" => Integer.to_string(t)})
    post_no_body(path("containers/#{enc_id(id)}/stop") <> "?" <> q)
  end

  @impl true
  def container_remove(id, opts) do
    force = if Keyword.get(opts, :force, false), do: "1", else: "0"
    q = URI.encode_query(%{"force" => force, "v" => "1"})
    delete(path("containers/#{enc_id(id)}") <> "?" <> q)
  end

  @impl true
  def container_pause(id), do: post_no_body(path("containers/#{enc_id(id)}/pause"))

  @impl true
  def container_unpause(id), do: post_no_body(path("containers/#{enc_id(id)}/unpause"))

  @impl true
  def container_stats(_id), do: {:error, :not_implemented}

  @impl true
  def container_exec(id, cmd, opts) when is_list(cmd) do
    workdir = Keyword.get(opts, :workdir)

    exec_body =
      %{
        "AttachStdout" => true,
        "AttachStderr" => true,
        "Cmd" => cmd
      }
      |> maybe_put("WorkingDir", workdir)
      |> Jason.encode!()

    with {:ok, exec_id} <- create_exec(id, exec_body),
         {:ok, raw} <- start_exec(exec_id) do
      {:ok, demux_stdout(raw)}
    end
  end

  @impl true
  def container_exec_with_exit(id, cmd, opts) when is_list(cmd) do
    workdir = Keyword.get(opts, :workdir)

    exec_body =
      %{
        "AttachStdout" => true,
        "AttachStderr" => true,
        "Cmd" => cmd
      }
      |> maybe_put("WorkingDir", workdir)
      |> Jason.encode!()

    with {:ok, exec_id} <- create_exec(id, exec_body),
         {:ok, raw} <- start_exec(exec_id),
         {:ok, exec_info} <- inspect_exec(exec_id) do
      exit_code = get_in(exec_info, ["ExitCode"]) || 0
      {:ok, %{stdout: demux_stdout(raw), exit_code: exit_code}}
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp inspect_exec(exec_id) do
    case get_json(path("exec/#{enc_id(exec_id)}/json")) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:error, _} = e -> e
    end
  end

  defp create_exec(container_id, body) do
    case request(:post, path("containers/#{enc_id(container_id)}/exec"), body, "application/json") do
      {:ok, %Finch.Response{status: status, body: resp}} when status in [200, 201] ->
        case Jason.decode(resp) do
          {:ok, %{"Id" => eid}} -> {:ok, eid}
          {:ok, other} -> {:error, {:unexpected_body, other}}
          {:error, _} -> {:error, :invalid_json}
        end

      {:ok, %Finch.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}

      {:error, _} = e ->
        e
    end
  end

  defp start_exec(exec_id) do
    body = Jason.encode!(%{"Detach" => false})

    case request(:post, path("exec/#{enc_id(exec_id)}/start"), body, "application/json") do
      {:ok, %Finch.Response{status: 200, body: raw}} ->
        {:ok, raw}

      {:ok, %Finch.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}

      {:error, _} = e ->
        e
    end
  end

  defp demux_stdout(data), do: demux_stdout(data, [])

  defp demux_stdout(<<type, _::binary-size(3), size::32-big, payload::binary-size(size), rest::binary>>, acc) do
    if type == 1 do
      demux_stdout(rest, [acc, payload])
    else
      demux_stdout(rest, acc)
    end
  end

  defp demux_stdout(_, acc), do: IO.iodata_to_binary(acc)

  @impl true
  def image_list(_opts) do
    case get_json(path("images/json")) do
      {:ok, list} when is_list(list) -> {:ok, list}
      {:ok, other} -> {:error, {:unexpected_body, other}}
      {:error, _} = e -> e
    end
  end

  @impl true
  def image_pull(ref) when is_binary(ref) do
    {name, tag} = split_image_ref(ref)
    q = URI.encode_query(%{"fromImage" => name, "tag" => tag})

    case request(:post, path("images/create") <> "?" <> q, "", "") do
      {:ok, %Finch.Response{status: 200}} -> :ok
      {:ok, %Finch.Response{status: s, body: b}} -> {:error, {:http, s, b}}
      {:error, _} = e -> e
    end
  end

  defp split_image_ref(ref) do
    case String.split(ref, ":", parts: 2) do
      [name, tag] -> {name, tag}
      [name] -> {name, "latest"}
    end
  end

  defp enc_id(id), do: URI.encode(id, &URI.char_unreserved?/1)

  defp path(suffix) do
    "/" <> api_version() <> "/" <> String.trim_leading(suffix, "/")
  end

  defp api_version do
    Application.get_env(:companion, :docker_api_version, "v1.45")
  end

  defp socket_path do
    Application.get_env(:companion, :docker_socket, "/var/run/docker.sock")
  end

  defp get_json(relative_path) do
    case request(:get, relative_path, "", "") do
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

  defp post_no_body(relative_path) do
    case request(:post, relative_path, "{}", "application/json") do
      {:ok, %Finch.Response{status: status}} when status in [200, 204] ->
        :ok

      {:ok, %Finch.Response{status: 304, body: ""}} ->
        :ok

      {:ok, %Finch.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}

      {:error, _} = e ->
        e
    end
  end

  defp delete(relative_path) do
    case request(:delete, relative_path, "", "") do
      {:ok, %Finch.Response{status: status}} when status in [200, 204] ->
        :ok

      {:ok, %Finch.Response{status: s, body: b}} ->
        {:error, {:http, s, b}}

      {:error, _} = e ->
        e
    end
  end

  defp request(method, relative_path, body, content_type) do
    sock = socket_path()
    url = "http://localhost" <> relative_path

    headers =
      [{"Host", "localhost"}] ++
        if(content_type != "", do: [{"Content-Type", content_type}], else: [])

    req = Finch.build(method, url, headers, body, unix_socket: sock)

    case Finch.request(req, @finch, receive_timeout: 120_000) do
      {:ok, %Finch.Response{} = resp} -> {:ok, resp}
      {:error, reason} -> {:error, reason}
    end
  end
end
