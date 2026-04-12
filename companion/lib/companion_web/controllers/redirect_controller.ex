defmodule CompanionWeb.RedirectController do
  use CompanionWeb, :controller

  def to_health(conn, _params) do
    redirect(conn, to: ~p"/health")
  end

  def to_warm(conn, _params) do
    redirect(conn, to: ~p"/warm")
  end

  def to_oss_agents(conn, _params) do
    redirect(conn, to: ~p"/oss-agents")
  end

  def to_machines(conn, _params) do
    redirect(conn, to: ~p"/machines")
  end
end
