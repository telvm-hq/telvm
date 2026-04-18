defmodule SpeedeelWeb.GuidesLive.Index do
  use SpeedeelWeb, :live_view

  import SpeedeelWeb.Layouts, only: [guides_nav: 1]

  @impl true
  def mount(_params, _session, socket) do
    pages = Speedeel.Guides.list_pages()
    {:ok, assign(socket, :pages, pages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 min-h-0">
      <.guides_nav pages={@pages} nav_active={:circuit} />
      <section class="flex-1 min-h-0 flex flex-col bg-[var(--telvm-shell-bg)]">
        <div class="speedeel-divider-neon shrink-0" aria-hidden="true"></div>
        <div class="flex-1 min-h-0 flex flex-col p-2 sm:p-3 gap-2 overflow-hidden">
          <div class="flex items-center justify-between gap-2 shrink-0">
            <h1 class="speedeel-circuit-title text-sm font-semibold text-[var(--telvm-shell-fg)] uppercase">
              circuit
            </h1>
            <span class="text-[10px] text-[var(--telvm-shell-muted)] hidden sm:inline">
              arrows · click track to focus
            </span>
          </div>
          <div
            id="speedeel-race"
            class="speedeel-race-wrap flex-1 min-h-[max(16rem,min(55vh,28rem))] rounded border border-[var(--telvm-shell-border)] bg-black relative overflow-hidden"
            phx-update="ignore"
            phx-hook="SpeedeelRace"
            tabindex="0"
            aria-label="Minimal racing circuit. Use arrow keys or on-screen controls."
          >
          </div>
        </div>
      </section>
    </div>
    """
  end
end
