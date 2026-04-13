defmodule CompanionWeb.Router do
  use CompanionWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {CompanionWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug :plug_fetch_query_params
  end

  def plug_fetch_query_params(conn, _opts), do: Plug.Conn.fetch_query_params(conn)

  scope "/", CompanionWeb do
    pipe_through :browser

    get "/", RedirectController, :to_health
    get "/topology", RedirectController, :to_warm
    get "/agent", RedirectController, :to_oss_agents
    get "/other-agents", RedirectController, :to_machines
    get "/telvm/api/fyi", FyiController, :show

    get "/telvm/morayeel/artifacts/:run_id/:filename", MorayeelArtifactController, :show

    live_session :default,
      layout: {CompanionWeb.Layouts, :app} do
      live "/health", StatusLive, :preflight
      live "/warm", StatusLive, :warm_assets
      live "/machines", StatusLive, :machines
      live "/oss-agents", StatusLive, :oss_agents
      live "/morayeel", StatusLive, :morayeel
      live "/images", StatusLive, :legacy_images_redirect
      live "/vm-manager-preflight", StatusLive, :legacy_preflight_redirect
      live "/certificate", StatusLive, :legacy_certificate_redirect
    end

    # Each /explore/:id tab is its own isolated BEAM process. Uses the bare root
    # layout so Monaco can fill the full browser viewport without app nav chrome.
    live_session :explorer, layout: {CompanionWeb.Layouts, :root} do
      live "/explore/:id", ExplorerLive, :index
    end
  end

  scope "/telvm/api", CompanionWeb do
    pipe_through :api

    get "/machines", MachineController, :index
    get "/machines/:id/stats", MachineController, :stats
    get "/machines/:id/logs", MachineController, :logs
    get "/machines/:id", MachineController, :show
    post "/machines", MachineController, :create
    post "/machines/:id/exec", MachineController, :exec
    post "/machines/:id/restart", MachineController, :restart
    post "/machines/:id/pause", MachineController, :pause
    post "/machines/:id/unpause", MachineController, :unpause
    delete "/machines/:id", MachineController, :delete
    get "/stream", MachineController, :stream
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:companion, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: CompanionWeb.Telemetry
    end
  end
end
