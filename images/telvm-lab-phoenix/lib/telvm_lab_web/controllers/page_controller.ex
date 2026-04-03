defmodule TelvmLabWeb.PageController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  def index(conn, _params) do
    json(conn, %{status: "ok", service: "telvm-lab", probe: "/"})
  end
end
