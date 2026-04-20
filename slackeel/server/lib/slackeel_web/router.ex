defmodule SlackeelWeb.Router do
  use SlackeelWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SlackeelWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_layout, html: {SlackeelWeb.Layouts, :app}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", SlackeelWeb do
    pipe_through :browser

    get "/", PageController, :redirect_root

    live_session :default, layout: {SlackeelWeb.Layouts, :app} do
      live "/models", ModelsLive
      live "/preflight", PreflightLive
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", SlackeelWeb do
  #   pipe_through :api
  # end
end
