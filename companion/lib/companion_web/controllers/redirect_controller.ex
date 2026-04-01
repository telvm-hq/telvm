defmodule CompanionWeb.RedirectController do
  use CompanionWeb, :controller

  def to_health(conn, _params) do
    redirect(conn, to: ~p"/health")
  end
end
