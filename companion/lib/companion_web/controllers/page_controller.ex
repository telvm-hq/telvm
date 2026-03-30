defmodule CompanionWeb.PageController do
  use CompanionWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
