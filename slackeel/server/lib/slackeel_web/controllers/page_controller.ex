defmodule SlackeelWeb.PageController do
  use SlackeelWeb, :controller

  def redirect_root(conn, _params) do
    redirect(conn, to: ~p"/preflight")
  end
end
