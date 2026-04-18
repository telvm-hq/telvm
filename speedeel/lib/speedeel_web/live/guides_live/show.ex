defmodule SpeedeelWeb.GuidesLive.Show do
  use SpeedeelWeb, :live_view

  import SpeedeelWeb.Layouts, only: [guides_nav: 1]

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    pages = Speedeel.Guides.list_pages()

    case Speedeel.Guides.read_markdown(slug) do
      {:ok, md} ->
        html = Speedeel.Guides.render_html(md)
        {:ok, assign(socket, html: html, slug: slug, pages: pages)}

      {:error, _} ->
        {:ok,
         socket
         |> put_flash(:error, "Guide not found")
         |> push_navigate(to: ~p"/")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-1 min-h-0">
      <.guides_nav pages={@pages} nav_active={{:guide, @slug}} />
      <section class="speedeel-scrollbar flex-1 min-h-0 overflow-y-auto bg-[var(--telvm-shell-bg)]">
        <div class="speedeel-divider-neon shrink-0" aria-hidden="true"></div>
        <div class="p-3 sm:p-4 max-w-3xl">
          <p class="mb-3">
            <.link
              class="text-[11px] telvm-accent-text hover:underline uppercase tracking-wide"
              navigate={~p"/"}
            >
              ← circuit
            </.link>
          </p>
          <article class="speedeel-prose telvm-prose-bar max-w-none text-[13px]">
            {Phoenix.HTML.raw(@html)}
          </article>
        </div>
      </section>
    </div>
    """
  end
end
