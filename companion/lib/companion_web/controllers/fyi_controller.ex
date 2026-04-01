defmodule CompanionWeb.FyiController do
  use CompanionWeb, :controller

  def show(conn, _params) do
    path = Application.app_dir(:companion, "priv/static/fyi.md")

    body =
      case File.read(path) do
        {:ok, content} -> content
        {:error, _} -> "# TELVM API\n\nFYI content is unavailable (missing priv/static/fyi.md).\n"
      end

    conn
    |> put_resp_content_type("text/markdown; charset=utf-8")
    |> send_resp(200, body)
  end
end
