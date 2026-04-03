defmodule TelvmLabWeb.Router do
  @moduledoc false
  use Phoenix.Router

  get "/", TelvmLabWeb.PageController, :index
end
