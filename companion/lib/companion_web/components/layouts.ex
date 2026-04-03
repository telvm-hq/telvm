defmodule CompanionWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use CompanionWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :inner_content, :global,
    doc: "LiveView injects rendered content here when using live_session layout"

  slot :inner_block,
    required: false,
    doc: "Controller templates pass content via the default inner block"

  def app(assigns) do
    ~H"""
    <div class="telvm-app-shell min-h-screen flex flex-col">
      <header class="navbar border-b px-4 sm:px-6 lg:px-8 shrink-0">
        <div class="flex-1">
          <a
            href={~p"/warm"}
            class="flex w-fit items-center gap-2 transition-colors telvm-accent-text hover:opacity-90"
          >
            <img src={~p"/images/logo.svg"} width="36" alt="" />
            <span class="text-sm font-semibold tracking-tight">telvm companion</span>
          </a>
        </div>
        
        <div class="flex-none">
          <ul class="flex flex-wrap px-1 gap-x-2 gap-y-1 items-center justify-end">
            <li>
              <a
                href={~p"/warm"}
                class="btn btn-ghost btn-sm telvm-nav-tab-idle border border-transparent hover:border-base-300"
              >
                Warm
              </a>
            </li>
            
            <li>
              <a
                href={~p"/machines"}
                class="btn btn-ghost btn-sm telvm-nav-tab-idle border border-transparent hover:border-base-300"
              >
                Machines
              </a>
            </li>
            
            <li>
              <a
                href={~p"/health"}
                class="btn btn-ghost btn-sm telvm-nav-tab-idle border border-transparent hover:border-base-300"
              >
                Pre-flight
              </a>
            </li>
            
            <li class="flex items-center gap-1"><.accent_toggle /> <.theme_toggle /></li>
          </ul>
        </div>
      </header>
      
      <main class="flex-1 px-4 py-6 sm:px-6 lg:px-8 transition-colors duration-200">
        <div class="mx-auto w-full max-w-7xl space-y-4">
          <%= if Map.has_key?(assigns, :inner_content) && assigns.inner_content do %>
            {@inner_content}
          <% else %>
            {render_slot(@inner_block)}
          <% end %>
        </div>
      </main>
       <.flash_group flash={@flash} />
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} /> <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
      
      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Accent family for Telvm shell (purple, yellow, green). Persists via `phx:accent` in root.html.heex.
  """
  def accent_toggle(assigns) do
    ~H"""
    <div
      class="hidden sm:flex flex-row items-center rounded-full border px-0.5 py-0.5 gap-0.5"
      style="border-color: var(--telvm-shell-border); background: var(--telvm-shell-elevated);"
      role="group"
      aria-label="Accent color"
    >
      <button
        type="button"
        class="px-2 py-1 rounded-full text-[10px] font-medium transition-colors telvm-accent-toggle-idle"
        phx-click={JS.dispatch("phx:set-accent")}
        data-phx-accent="purple"
        title="Purple accent"
      >
        P
      </button>
      <button
        type="button"
        class="px-2 py-1 rounded-full text-[10px] font-medium transition-colors telvm-accent-toggle-idle"
        phx-click={JS.dispatch("phx:set-accent")}
        data-phx-accent="yellow"
        title="Yellow accent"
      >
        Y
      </button>
      <button
        type="button"
        class="px-2 py-1 rounded-full text-[10px] font-medium transition-colors telvm-accent-toggle-idle"
        phx-click={JS.dispatch("phx:set-accent")}
        data-phx-accent="green"
        title="Green accent"
      >
        G
      </button>
    </div>
    """
  end

  @doc """
  Light / dark theme toggle (explicit only; no OS “system” mode). Themes are defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/2 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=dark]_&]:left-1/2 transition-[left]" />
      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
        title="Light theme"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
      <button
        class="flex p-2 cursor-pointer w-1/2"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
        title="Dark theme"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
