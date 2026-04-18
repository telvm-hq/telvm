defmodule SpeedeelWeb.MinigamesLive.Index do
  use SpeedeelWeb, :live_view

  import SpeedeelWeb.Layouts, only: [guides_nav: 1]

  @impl true
  def mount(_params, _session, socket) do
    pages = Speedeel.Guides.list_pages()
    {:ok, assign(socket, pages: pages)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 min-h-0">
      <.guides_nav pages={@pages} nav_active={:minigames} />
      <section class="speedeel-scrollbar flex-1 min-h-0 overflow-y-auto bg-[var(--telvm-shell-bg)]">
        <div class="speedeel-divider-neon shrink-0" aria-hidden="true"></div>
        <div class="speedeel-dungeon-root p-3 sm:p-4 max-w-4xl mx-auto flex flex-col gap-4">
          <header class="space-y-2">
            <p class="text-[10px] uppercase tracking-[0.35em] text-[var(--dungeon-lichen)] m-0">
              orientation pamphlet · act i
            </p>
            <h1 class="text-lg sm:text-xl font-semibold text-[var(--dungeon-warm-milk)] tracking-tight m-0">
              The Hospitality Catacombs
            </h1>
            <p class="text-[13px] leading-relaxed text-[var(--dungeon-lichen)] max-w-2xl m-0">
              Thank you for visiting our softly lit basement. Act I names our most honored quartet—
              <span class="text-[var(--dungeon-warm-milk)]">Daytona</span>,
              <span class="text-[var(--dungeon-warm-milk)]">E2B</span>,
              <span class="text-[var(--dungeon-warm-milk)]">Modal</span>,
              and <span class="text-[var(--dungeon-warm-milk)]">Loft Labs</span> (vCluster / nested planes)—each a future minigame devoted to one question:
              <span class="text-[var(--dungeon-warm-milk)]"> who holds the truth when something starts, stops, or whispers outbound? </span>
              Later acts add
              <span class="text-[var(--dungeon-warm-milk)]">Lovable</span>,
              <span class="text-[var(--dungeon-warm-milk)]">GitHub Codespaces</span>,
              <span class="text-[var(--dungeon-warm-milk)]">Gitpod</span> /
              <span class="text-[var(--dungeon-warm-milk)]">Coder</span>,
              <span class="text-[var(--dungeon-warm-milk)]">Runloop</span>, hyperscaler notebooks, and edge-style cloisters.
              We keep the sunny circuit upstairs and only ask you to remove your shoes and your moat slides.
            </p>
          </header>

          <div
            id="speedeel-dungeon-stage"
            class="speedeel-dungeon-stage shrink-0 min-h-[max(14rem,min(42vh,22rem))] rounded relative overflow-hidden"
            phx-update="ignore"
            phx-hook="SpeedeelDungeon"
            tabindex="0"
            aria-label="Catacombs stage. Pixel baseline for upcoming minigames."
          >
          </div>
          <p class="text-[10px] text-[var(--dungeon-lichen)] m-0">
            tip · click the stone to focus the stage (arrows reserved for later guests)
          </p>

          <section class="space-y-3">
            <h2 class="text-[11px] uppercase tracking-[0.28em] text-[var(--dungeon-sour-honey)] m-0">
              act i — honored quartet
            </h2>
            <ul class="grid gap-2 sm:grid-cols-2 text-[12px] text-[var(--dungeon-warm-milk)] m-0 pl-0 list-none">
              <li class="speedeel-dungeon-card rounded px-3 py-2">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Daytona</span>
                — <span class="italic text-[var(--dungeon-lichen)]">The Long Nap Hallway</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-1">pit stops, save-state trust, lifecycle naps</span>
                <ul class="speedeel-dungeon-receipts mt-2 space-y-0.5 text-[10px] m-0 pl-0 list-none">
                  <li>
                    <a
                      href="https://github.com/daytonaio/daytona/issues/2390"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Sandbox stuck in starting, cannot delete"
                    >#2390 · stuck starting</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/daytonaio/daytona/issues/3294"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Sandboxes stuck Deleting, quota blocked"
                    >#3294 · stuck deleting</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/daytonaio/daytona/issues/4142"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="502/400 during stop transition, misleading status"
                    >#4142 · stop transition</a>
                  </li>
                </ul>
              </li>
              <li class="speedeel-dungeon-card rounded px-3 py-2">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">E2B</span>
                — <span class="italic text-[var(--dungeon-lichen)]">The Telemetry Tea Party</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-1">API fog, dashboards with feelings</span>
                <ul class="speedeel-dungeon-receipts mt-2 space-y-0.5 text-[10px] m-0 pl-0 list-none">
                  <li>
                    <a
                      href="https://github.com/e2b-dev/E2B/issues/646"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="No first-class structured channel sandbox to client"
                    >#646 · events channel</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/e2b-dev/E2B/issues/884"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Pause / resume reliability"
                    >#884 · pause resume</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/e2b-dev/E2B/issues/1074"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Long-running / background task ergonomics"
                    >#1074 · long running</a>
                  </li>
                </ul>
              </li>
              <li class="speedeel-dungeon-card rounded px-3 py-2">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Modal</span>
                — <span class="italic text-[var(--dungeon-lichen)]">The Burst Candy Shop</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-1">rented seconds, sugar-rush economics</span>
                <ul class="speedeel-dungeon-receipts mt-2 space-y-0.5 text-[10px] m-0 pl-0 list-none">
                  <li>
                    <a
                      href="https://github.com/modal-labs/modal-examples/issues/1264"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Open issue: running Modal examples on Windows (Flux Kontext)"
                    >#1264 · windows examples</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/modal-labs/modal-examples/issues/1135"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Open issue: custom nodes in examples"
                    >#1135 · custom nodes</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/modal-labs/modal-examples/issues/1105"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Open issue: auth with vLLM inference example"
                    >#1105 · vllm auth</a>
                  </li>
                </ul>
              </li>
              <li class="speedeel-dungeon-card rounded px-3 py-2">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Loft Labs</span>
                — <span class="italic text-[var(--dungeon-lichen)]">The Nested Keep</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-1">vCluster sync, nested planes, tenant ghosts</span>
                <ul class="speedeel-dungeon-receipts mt-2 space-y-0.5 text-[10px] m-0 pl-0 list-none">
                  <li>
                    <a
                      href="https://github.com/loft-sh/vcluster/issues/3805"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Open issue: install-standalone D-Bus race in Docker containers"
                    >#3805 · dbus docker</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/loft-sh/vcluster/issues/3756"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Open issue: fake-node syncer, pods stuck on deleted host node"
                    >#3756 · unknown node</a>
                  </li>
                  <li>
                    <a
                      href="https://github.com/loft-sh/vcluster/issues/3744"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="text-[var(--dungeon-lichen)] hover:text-[var(--dungeon-sour-honey)] underline underline-offset-2 block truncate"
                      title="Open issue: etcd errors on vCluster start (0.33.1)"
                    >#3744 · etcd start</a>
                  </li>
                </ul>
              </li>
            </ul>
          </section>

          <section class="space-y-2">
            <h2 class="text-[11px] uppercase tracking-[0.28em] text-[var(--dungeon-lichen)] m-0">
              act ii–iii — six more doors (locked until polite notice)
            </h2>
            <ul class="grid gap-2 sm:grid-cols-2 text-[11px] text-[var(--dungeon-warm-milk)] m-0 pl-0 list-none">
              <li class="speedeel-dungeon-card rounded px-2 py-1.5">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Lovable</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-0.5 italic">The Purple Confetti Closet</span>
              </li>
              <li class="speedeel-dungeon-card rounded px-2 py-1.5">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">GitHub Codespaces</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-0.5 italic">The Deep-Link Maze</span>
              </li>
              <li class="speedeel-dungeon-card rounded px-2 py-1.5">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Gitpod / Coder</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-0.5 italic">The Ephemeral Foyer</span>
              </li>
              <li class="speedeel-dungeon-card rounded px-2 py-1.5">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Runloop</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-0.5 italic">The Devbox Annex</span>
              </li>
              <li class="speedeel-dungeon-card rounded px-2 py-1.5">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Hyperscaler notebooks</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-0.5 italic">The Notebook Nursery</span>
              </li>
              <li class="speedeel-dungeon-card rounded px-2 py-1.5">
                <span class="text-[var(--dungeon-old-gold)] font-semibold">Edge / Workers-style</span>
                <span class="block text-[10px] text-[var(--dungeon-lichen)] mt-0.5 italic">The Coldstart Cloister</span>
              </li>
            </ul>
            <p class="text-[10px] text-[var(--dungeon-lichen)] m-0">
              Each gets a tiny key when the quartet says hello first. The guest list is closed—ten chambers only.
            </p>
          </section>

          <footer class="speedeel-dungeon-footer text-[10px] text-[var(--dungeon-lichen)] pt-3">
            Receipts for the loudest guests live in the repo’s
            <a
              class="text-[var(--dungeon-sour-honey)] underline underline-offset-2"
              href="https://github.com/telvm-hq/telvm/blob/main/speedeel/README.md"
              rel="noopener noreferrer"
              target="_blank"
            >speedeel README</a>
            (and the sunny
            <.link class="text-[var(--dungeon-sour-honey)] underline underline-offset-2" navigate={~p"/"}>circuit</.link>
            if you miss the light). Long-form tea is in telvm’s wiki. Companion stays on :4000—this is only the guest map.
          </footer>
        </div>
      </section>
    </div>
    """
  end
end
