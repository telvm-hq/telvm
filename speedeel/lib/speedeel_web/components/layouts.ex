defmodule SpeedeelWeb.Layouts do
  @moduledoc false
  use SpeedeelWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true
  attr :inner_content, :global

  def app(assigns) do
    ~H"""
    <div class="telvm-app-shell min-h-full h-full flex flex-col font-mono text-[13px] leading-snug">
      <header class="border-b border-[var(--telvm-shell-border)] shrink-0 flex items-center gap-3 px-3 py-2 min-h-[2.75rem]">
        <div class="flex flex-1 items-center gap-3 min-w-0">
          <a
            class="telvm-accent-text font-semibold tracking-[0.12em] uppercase shrink-0 text-[13px]"
            href={~p"/"}
          >
            speedeel
          </a>
          <span class="telvm-accent-dim-text text-[9px] uppercase tracking-[0.22em] truncate opacity-90">
            guides / labs · not Companion
          </span>
        </div>
      </header>

      <main class="flex-1 min-h-0 flex flex-col overflow-hidden">
        {@inner_content}
      </main>

      <footer class="border-t border-[var(--telvm-shell-border)] shrink-0 bg-[var(--telvm-shell-elevated)]">
        <div class="speedeel-divider-neon" aria-hidden="true"></div>
        <div class="px-3 py-2 text-[10px] uppercase tracking-[0.2em] flex items-center gap-x-3 gap-y-1.5 flex-wrap text-[var(--telvm-shell-muted)]">
          <a
            href="https://cursor.com"
            rel="noopener noreferrer"
            target="_blank"
            class="telvm-accent-text inline-flex items-center gap-1.5 no-underline hover:opacity-95 telvm-accent-ring rounded px-0.5 -mx-0.5"
          >
            <img
              src={~p"/images/cursor-mark.svg"}
              alt=""
              width="14"
              height="14"
              class="h-3.5 w-3.5 shrink-0 opacity-95"
              decoding="async"
            />
            <span class="underline underline-offset-2">Built with Cursor</span>
          </a>
          <span class="text-[var(--telvm-shell-muted)]" aria-hidden="true">·</span>
          <a
            href="https://telvm.com"
            rel="noopener noreferrer"
            target="_blank"
            class="telvm-accent-text no-underline hover:opacity-95 telvm-accent-ring rounded px-0.5 -mx-0.5"
          >
            <span class="underline underline-offset-2">sponsored by telvm.com</span>
          </a>
          <span class="normal-case tracking-normal opacity-90">companion :4000</span>
        </div>
      </footer>

      <.flash_group flash={@flash} id="flash" />
    </div>
    """
  end

  attr :pages, :list, required: true
  @doc """
  `:circuit` — home / Three.js showcase.
  `:minigames` — Hospitality Catacombs.
  `{:guide, slug}` — markdown guide.
  """
  attr :nav_active, :any, required: true

  def guides_nav(assigns) do
    ~H"""
    <aside
      class="w-60 shrink-0 border-r border-[var(--telvm-shell-border)] flex flex-col min-h-0 bg-[var(--telvm-shell-elevated)] shadow-[inset_-1px_0_0_0_var(--telvm-cyber-edge)]"
    >
      <div class="px-2 pt-2 pb-2 border-b border-[var(--telvm-shell-border)]">
        <div class="max-h-28 w-full overflow-hidden rounded-lg border border-[var(--telvm-accent-border)] shadow-[0_0_18px_-6px_rgba(255,122,24,0.35)] bg-[var(--telvm-panel-bg)]">
          <img
            src={~p"/images/speedeel_mascot_core.png"}
            alt="Speedeel mascot"
            width="480"
            height="270"
            class="max-h-28 w-full object-contain object-left block align-bottom"
            decoding="async"
          />
        </div>
      </div>
      <div class="px-2 py-2 border-b border-[var(--telvm-shell-border)] flex items-center gap-2 min-w-0">
        <img
          src={~p"/images/speedeel_double_checker.svg"}
          alt=""
          width="1280"
          height="640"
          class="speedeel-double-flag h-6 w-auto shrink-0"
          decoding="async"
        />
        <p class="text-[10px] telvm-accent-dim-text uppercase tracking-[0.28em] m-0 truncate">guides</p>
      </div>
      <div class="px-2 py-2 flex-1 min-h-0 flex flex-col">
        <%= if @pages == [] do %>
          <p class="text-[11px] text-[var(--telvm-shell-muted)] mb-2">No .md in root.</p>
        <% end %>
        <nav class="speedeel-scrollbar flex flex-col gap-0.5 max-h-[50vh] overflow-y-auto overflow-x-hidden pr-1.5 -mr-0.5">
          <.link
            navigate={~p"/"}
            class={[
              "block rounded border px-2 py-1.5 text-[11px] leading-tight transition-all duration-150",
              @nav_active == :circuit && "telvm-nav-tab-active border",
              @nav_active != :circuit && "telvm-nav-tab-idle border border-transparent"
            ]}
          >
            <span class="text-[var(--telvm-shell-fg)]">circuit</span>
            <span class="block text-[10px] text-[var(--telvm-shell-muted)]">home / game</span>
          </.link>
          <.link
            navigate={~p"/minigames"}
            class={[
              "block rounded border px-2 py-1.5 text-[11px] leading-tight transition-all duration-150",
              @nav_active == :minigames && "telvm-nav-tab-active border",
              @nav_active != :minigames && "telvm-nav-tab-idle border border-transparent"
            ]}
          >
            <span class="text-[var(--telvm-shell-fg)]">catacombs</span>
            <span class="block text-[10px] text-[var(--telvm-shell-muted)]">guest map / soon</span>
          </.link>
          <%= for p <- @pages do %>
            <.link
              navigate={~p"/guides/#{p.slug}"}
              class={[
                "block rounded border px-2 py-1.5 text-[11px] leading-tight transition-all duration-150",
                @nav_active == {:guide, p.slug} && "telvm-nav-tab-active border",
                @nav_active != {:guide, p.slug} && "telvm-nav-tab-idle border border-transparent"
              ]}
            >
              <span class="text-[var(--telvm-shell-fg)]">{p.title}</span>
              <span class="block text-[10px] text-[var(--telvm-shell-muted)] truncate">{p.basename}</span>
            </.link>
          <% end %>
        </nav>
      </div>
    </aside>
    """
  end
end
