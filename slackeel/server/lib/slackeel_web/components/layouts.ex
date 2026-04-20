defmodule SlackeelWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SlackeelWeb, :html

  embed_templates "layouts/*"

  @doc """
  Live headroom + status readout for the top nav (driven by LiveView `snapshot` assign).
  """
  attr :snapshot, :map, required: true

  def preflight_nav_strip(assigns) do
    assigns =
      assign(assigns, :variance_pct, variance_pct_nav())

    ~H"""
    <div
      class="grid min-w-0 max-w-full grid-cols-2 gap-x-3 gap-y-0 overflow-x-auto rounded-sm border px-2 py-1 font-mono text-[9px] leading-snug sm:gap-x-4"
      style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-shell-elevated) 48%, transparent);"
      title="Preflight snapshot (updates with Refresh / navigation)"
    >
      <div class="min-w-0 border-r border-[color-mix(in_oklch,var(--telvm-shell-border)_60%,transparent)] pr-2 sm:pr-3">
        <div class="text-[8px] uppercase tracking-[0.12em] text-[var(--telvm-shell-muted)]">
          Headroom
        </div>
        <div class="truncate telvm-accent-dim-text" title={origin_label_nav(@snapshot.origin)}>
          {origin_label_nav(@snapshot.origin)}
        </div>
        <div class="tabular-nums text-[var(--telvm-shell-fg)]">
          {format_nav_gib(@snapshot.effective_free_bytes)} free
        </div>
        <div class="text-[8px] leading-tight text-[var(--telvm-shell-muted)]">
          1024³ GiB · floor = bottleneck.
        </div>
      </div>
      <div class="min-w-0 pl-0">
        <div class="text-[8px] uppercase tracking-[0.12em] text-[var(--telvm-shell-muted)]">
          Status
        </div>
        <div class="text-[var(--telvm-shell-fg)]">
          +{@variance_pct}% ·
          <code
            class="rounded px-0.5 text-[8px]"
            style="background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
          >
            :preflight_disk_variance
          </code>
        </div>
        <p
          :if={@snapshot.remote_error}
          class="truncate text-[8px] leading-tight telvm-text-warn"
          title={inspect(@snapshot.remote_error)}
        >
          {inspect(@snapshot.remote_error, limit: 120)}
        </p>
        <code class="text-[8px] text-[var(--telvm-shell-muted)]">:preflight_metrics_url</code>
      </div>
    </div>
    """
  end

  defp variance_pct_nav do
    v = Application.get_env(:slackeel, :preflight_disk_variance, 1.15)
    round(v * 100 - 100)
  end

  defp format_nav_gib(bytes) when is_integer(bytes) do
    g = bytes / 1_073_741_824
    :erlang.float_to_binary(g, decimals: 2) <> " GiB"
  end

  defp origin_label_nav(:telvm_network_agent), do: "telvm-network-agent (HTTP)"
  defp origin_label_nav(:http_metrics), do: "HTTP metrics URL"
  defp origin_label_nav(:local_beam), do: "Local BEAM (:disksup fallback)"
  defp origin_label_nav(other), do: inspect(other)

  defp can_run_verify?(assigns) do
    needs? = Map.get(assigns, :probe_prompt_needs_commit, false)
    locked = Map.get(assigns, :probe_prompt_locked, "") |> to_string() |> String.trim()
    not needs? and locked != ""
  end

  @doc """
  Ollama verify strip for `/preflight` only (`show` false elsewhere).
  Events: `set_probe_prompt`, `commit_probe_prompt`, `verify_integration`, `verify_cancel` in `PreflightLive`.
  """
  attr :show, :boolean, default: false
  attr :verify_running, :boolean, default: false
  attr :probe_prompt_draft, :string, default: ""
  attr :probe_prompt_locked, :string, default: ""
  attr :probe_prompt_needs_commit, :boolean, default: false

  def ollama_verify_hud(assigns) do
    assigns =
      assigns
      |> assign(:ollama_url, Slackeel.Ollama.Config.ollama_base_url() |> to_string())
      |> assign(:can_run_check, can_run_verify?(assigns))

    ~H"""
    <div
      :if={@show}
      class={[
        "telvm-ollama-hud shrink-0 border-b font-mono text-[10px] sm:text-[11px] leading-tight transition-[box-shadow,background-color] duration-200",
        @verify_running &&
          "shadow-[inset_0_0_0_1px_color-mix(in_oklch,var(--telvm-accent)_28%,transparent)]"
      ]}
      style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-shell-elevated) 55%, transparent);"
    >
      <div class="mx-auto max-w-7xl px-2 py-1.5 sm:px-3">
        <div class="flex flex-wrap items-center gap-x-3 gap-y-2 border-b border-[color-mix(in_oklch,var(--telvm-shell-border)_55%,transparent)] pb-2">
          <div class="flex min-w-0 flex-1 flex-wrap items-baseline gap-x-2 gap-y-0.5">
            <span class="shrink-0 font-semibold uppercase tracking-[0.16em] telvm-accent-text">verify</span>
            <span
              class="min-w-0 truncate text-[var(--telvm-shell-muted)]"
              title={@ollama_url}
            >
              {@ollama_url}
            </span>
          </div>
        </div>

        <div class="flex flex-wrap items-end justify-end gap-2 pt-2">
          <form
            phx-change="set_probe_prompt"
            class="flex min-w-0 w-full flex-1 flex-wrap items-end gap-x-2 gap-y-1 sm:w-auto sm:min-w-[min(100%,28rem)] sm:flex-1"
          >
            <label for="slackeel-probe-draft" class="sr-only">
              Probe prompt (edit, then lock, then check)
            </label>
            <textarea
              id="slackeel-probe-draft"
              name="prompt_draft"
              disabled={@verify_running}
              rows="2"
              phx-debounce="300"
              class={[
                "telvm-accent-ring box-border max-h-24 min-h-[2.75rem] min-w-[12rem] w-full flex-1 resize-y rounded-sm border px-2 py-1.5 font-mono text-[10px] leading-snug outline-none sm:max-w-xl",
                @verify_running && "cursor-not-allowed opacity-55"
              ]}
              style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-shell-bg) 45%, transparent); color: var(--telvm-shell-fg);"
            >{@probe_prompt_draft}</textarea>
            <p class="w-full text-[8px] leading-tight text-[var(--telvm-shell-muted)] sm:w-auto sm:min-w-[8rem] sm:flex-initial">
              Edit → <span class="font-semibold text-[var(--telvm-shell-fg)]">lock</span>
              → <span class="font-semibold text-[var(--telvm-shell-fg)]">check</span>.
              <span :if={@probe_prompt_needs_commit} class="telvm-accent-text"> Unsaved edits.</span>
              <span :if={not @probe_prompt_needs_commit and String.trim(@probe_prompt_locked) != ""} class="telvm-text-ok">
                Ready.
              </span>
            </p>
          </form>

          <div class="flex w-full shrink-0 flex-wrap items-center justify-end gap-1.5 sm:w-auto">
            <button
              type="button"
              phx-click="commit_probe_prompt"
              disabled={@verify_running or not @probe_prompt_needs_commit}
              class={[
                "rounded-sm border px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wide",
                @probe_prompt_needs_commit && not @verify_running && "telvm-btn-secondary border-[color-mix(in_oklch,var(--telvm-accent)_45%,transparent)]",
                (not @probe_prompt_needs_commit or @verify_running) && "cursor-not-allowed opacity-45 border-[color-mix(in_oklch,var(--telvm-shell-border)_70%,transparent)] text-[var(--telvm-shell-muted)]"
              ]}
              title="Apply draft — required before check uses your text"
            >
              lock
            </button>
            <button
              type="button"
              phx-click="verify_integration"
              disabled={@verify_running or not @can_run_check}
              class={[
                "rounded-sm border px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wide telvm-btn-primary",
                (@verify_running or not @can_run_check) && "cursor-not-allowed opacity-55"
              ]}
              title={
                cond do
                  @verify_running -> "Run in progress"
                  @probe_prompt_needs_commit -> "Lock your prompt before check"
                  String.trim(@probe_prompt_locked) == "" -> "Set and lock a non-empty prompt"
                  true -> "Run integration check with locked prompt"
                end
              }
            >
              {if @verify_running, do: "run…", else: "check"}
            </button>
            <button
              :if={@verify_running}
              type="button"
              phx-click="verify_cancel"
              class="rounded-sm border px-2 py-1.5 text-[10px] font-semibold uppercase tracking-wide telvm-btn-secondary"
            >
              stop
            </button>
            <details class="group relative">
              <summary class="cursor-pointer list-none rounded-sm border border-[color-mix(in_oklch,var(--telvm-shell-border)_70%,transparent)] bg-[color-mix(in_oklch,var(--telvm-shell-bg)_35%,transparent)] px-2 py-1 text-[9px] uppercase tracking-wide text-[var(--telvm-shell-muted)] marker:content-none hover:text-[var(--telvm-shell-fg)] [&::-webkit-details-marker]:hidden">
                ?
              </summary>
              <div class="absolute right-0 z-10 mt-1 w-[min(100vw-2rem,22rem)] space-y-1.5 rounded-sm border p-2 text-[9px] leading-relaxed text-[var(--telvm-shell-muted)] shadow-lg sm:left-0 sm:right-auto sm:w-80"
                style="border-color: var(--telvm-shell-border); background: var(--telvm-panel-bg);"
              >
                <p class="text-[var(--telvm-shell-fg)]">
                  Type your probe → <strong class="text-[var(--telvm-shell-fg)]">lock</strong> arms that exact string for the run →
                  <strong class="text-[var(--telvm-shell-fg)]">check</strong>
                  pulls / probes / unloads. Default is
                  <code class="rounded px-0.5 text-[8px]" style="background: var(--telvm-input-bg);">
                    integration_verify_prompt
                  </code>
                  from config until you change it.
                </p>
                <p class="border-t pt-1.5 text-[8px]" style="border-color: var(--telvm-shell-border);">
                  Stop finishes the current request if needed, then skips the rest.
                </p>
              </div>
            </details>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

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
  Light / dark theme toggle (explicit only; no OS “system” mode).
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
