defmodule CompanionWeb.MorayeelArtifactController do
  use CompanionWeb, :controller

  @allowed_files ~w(storageState.json run.json last.png network.har runner.log)

  def show(conn, %{"run_id" => run_id, "filename" => file}) do
    cond do
      validate_run_id(run_id) == :error ->
        send_resp(conn, 404, "not found")

      file not in @allowed_files ->
        send_resp(conn, 404, "not found")

      true ->
        base = Application.get_env(:companion, Companion.MorayeelRunner, []) |> Keyword.get(:artifacts_dir, "/morayeel-runs")
        path = Path.join([base, run_id, file])

        if File.exists?(path) and File.regular?(path) do
          send_artifact_file(conn, path)
        else
          send_resp(conn, 404, "not found")
        end
    end
  end

  defp validate_run_id(id) when is_binary(id) do
    if Regex.match?(~r/^[a-f0-9]{16}$/, id), do: {:ok, id}, else: :error
  end

  defp validate_run_id(_), do: :error

  defp send_artifact_file(conn, path) do
    mime = MIME.from_path(path)

    conn
    |> put_resp_content_type(mime || "application/octet-stream")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{Path.basename(path)}"))
    |> send_file(200, path)
  end
end
