defmodule SpeedeelWeb.Router do
  use SpeedeelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SpeedeelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", SpeedeelWeb do
    pipe_through :browser

    live_session :guides, layout: {SpeedeelWeb.Layouts, :app} do
      live "/", GuidesLive.Index, :index
      live "/minigames", MinigamesLive.Index, :index
      live "/guides/:slug", GuidesLive.Show, :show
    end
  end
end
