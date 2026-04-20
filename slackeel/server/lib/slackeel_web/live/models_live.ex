defmodule SlackeelWeb.ModelsLive do
  @moduledoc """
  Manifest table; headroom/status live in the app nav (`Layouts.preflight_nav_strip/1`).
  Same `Slackeel.Preflight.snapshot/0` as Pre-flight.
  """
  use SlackeelWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    socket =
      load(socket)
      |> assign(:metrics_live, false)
      |> assign(:highlight_ollama, nil)

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Slackeel.PubSub, Slackeel.Ollama.ProbeMetrics.pubsub_topic())
        assign(socket, :metrics_live, true)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_info({:probe_metric, model, row}, socket) when is_binary(model) and is_map(row) do
    probe_metrics = Map.put(socket.assigns.probe_metrics, model, row)
    _ = Process.send_after(self(), {:clear_metric_highlight, model}, 850)

    {:noreply,
     socket
     |> assign(:probe_metrics, probe_metrics)
     |> assign(:refreshed_at, DateTime.utc_now())
     |> assign(:highlight_ollama, model)}
  end

  def handle_info({:clear_metric_highlight, model}, socket) when is_binary(model) do
    if socket.assigns[:highlight_ollama] == model do
      {:noreply, assign(socket, :highlight_ollama, nil)}
    else
      {:noreply, socket}
    end
  end

  defp load(socket) do
    metrics_live = Map.get(socket.assigns, :metrics_live, false)
    highlight_ollama = Map.get(socket.assigns, :highlight_ollama, nil)

    case Slackeel.Preflight.snapshot() do
      {:ok, snap} ->
        assign(socket,
          page_title: "Models",
          top_bar_title: nil,
          error: nil,
          snapshot: snap,
          refreshed_at: DateTime.utc_now(),
          show_ollama_hud: false,
          verify_running: false,
          probe_metrics: Slackeel.Ollama.ProbeMetrics.all_map(),
          metrics_live: metrics_live,
          highlight_ollama: highlight_ollama
        )

      {:error, reason} ->
        assign(socket,
          page_title: "Models",
          top_bar_title: nil,
          error: inspect(reason),
          snapshot: nil,
          refreshed_at: DateTime.utc_now(),
          show_ollama_hud: false,
          verify_running: false,
          probe_metrics: Slackeel.Ollama.ProbeMetrics.all_map(),
          metrics_live: metrics_live,
          highlight_ollama: highlight_ollama
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell slac-tactical slac-preflight-view flex min-h-0 flex-1 flex-col gap-3 px-3 py-3 sm:px-4 sm:py-4">
      <div class="shrink-0">
        <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 font-mono">
          <h1 class="text-xs font-semibold uppercase tracking-wide telvm-accent-text sm:text-sm">
            Models
          </h1>
          <span :if={@refreshed_at} class="telvm-muted-xs text-[10px] tracking-tight">
            {Calendar.strftime(@refreshed_at, "%m-%d %H:%M")} UTC
          </span>
        </div>

        <div
          :if={@error}
          class="mt-2 rounded-sm border px-2 py-1 text-[11px] telvm-text-danger-ink"
          style="border-color: var(--telvm-danger-border); background: var(--telvm-danger-bg);"
        >
          SNAPSHOT FAIL — {@error}
        </div>
      </div>

      <div :if={@snapshot} class="flex min-h-0 flex-1 flex-col gap-2 font-mono">
        <section class="slac-card slac-card--models-manifest telvm-verify-card telvm-panel-border flex min-h-0 flex-1 flex-col overflow-hidden border border-[color:var(--telvm-shell-border)]">
          <div class="slac-card__hdr flex shrink-0 !py-1 flex-wrap items-center justify-between gap-2 text-[9px] font-semibold uppercase tracking-[0.12em] text-[var(--telvm-shell-muted)]">
            <span>Manifest</span>
            <span
              :if={@metrics_live}
              class="rounded-sm border px-1.5 py-0.5 text-[8px] font-bold tracking-wider telvm-accent-text"
              style="border-color: color-mix(in oklch, var(--telvm-accent) 45%, transparent); animation: telvm-live-pulse 2s ease-in-out infinite;"
            >
              LIVE
            </span>
          </div>
          <div class="slac-card__body flex min-h-0 flex-1 flex-col gap-0 overflow-hidden !pt-1.5">
            <div class="min-h-0 flex-1 overflow-y-auto overflow-x-auto">
              <table class="w-full text-left text-[10px] sm:text-xs">
                <thead class="sticky top-0 z-[1] border-b border-[color:var(--telvm-shell-border)] bg-[color-mix(in_oklch,var(--telvm-shell-elevated)_88%,var(--telvm-shell-bg))]">
                  <tr>
                    <th class="py-1 pr-1 font-medium text-[var(--telvm-shell-muted)]">Fam</th>
                    <th class="py-1 px-0.5 font-mono">Model</th>
                    <th class="py-1 px-0.5 text-right font-mono">~Pull</th>
                    <th class="py-1 px-0.5 text-right font-mono">Buf</th>
                    <th class="py-1 px-0.5 text-right font-mono">tok/s</th>
                    <th class="py-1 pl-0.5">OK</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={m <- @snapshot.models}
                    class={[
                      "border-b border-[color:var(--telvm-shell-border)]/50",
                      if(m.enabled?, do: "", else: "opacity-55"),
                      @highlight_ollama == m.ollama && "telvm-models-row--metric-flash"
                    ]}
                  >
                    <td class="max-w-[4rem] truncate py-1 pr-1 align-top sm:max-w-none">{m.family}</td>
                    <td class="py-1 px-0.5 font-mono align-top break-all">{m.ollama}</td>
                    <td class="whitespace-nowrap py-1 px-0.5 text-right font-mono">{format_gib(m.approx_pull_bytes)}</td>
                    <td class="whitespace-nowrap py-1 px-0.5 text-right font-mono">{format_gib(m.margin_bytes)}</td>
                    <td
                      class="max-w-[6rem] whitespace-nowrap py-1 px-0.5 text-right font-mono align-top text-[9px] sm:text-[10px]"
                      title={probe_metrics_title(@probe_metrics, m.ollama)}
                    >
                      {probe_tok_s(@probe_metrics, m.ollama)}
                    </td>
                    <td class="whitespace-nowrap py-1 pl-0.5">
                      <span
                        :if={m.enabled?}
                        class="text-[9px] font-semibold uppercase tracking-wide telvm-text-ok"
                      >
                        Y
                      </span>
                      <span
                        :if={not m.enabled?}
                        class="text-[9px] uppercase tracking-wide telvm-muted-xs"
                      >
                        N
                      </span>
                    </td>
                  </tr>
                </tbody>
              </table>
            </div>
            <p class="shrink-0 border-t border-[color:var(--telvm-shell-border)] pt-1 text-[9px] leading-snug text-[var(--telvm-shell-muted)]">
              Gate vs headroom · no unload.
              tok/s streams live while Pre-flight verify runs (this page subscribes); last values kept in memory until restart.
            </p>
          </div>
        </section>
      </div>
    </div>
    """
  end

  defp format_gib(bytes) when is_integer(bytes) do
    g = bytes / 1_073_741_824
    :erlang.float_to_binary(g, decimals: 2) <> " GiB"
  end

  defp probe_tok_s(metrics, ollama) when is_map(metrics) and is_binary(ollama) do
    case Map.get(metrics, ollama) do
      %{tokens_per_sec: tps} when is_number(tps) ->
        :erlang.float_to_binary(tps * 1.0, decimals: 1)

      _ ->
        "—"
    end
  end

  defp probe_metrics_title(metrics, ollama) when is_map(metrics) and is_binary(ollama) do
    case Map.get(metrics, ollama) do
      %{tokens_per_sec: tps, duration_ms: d, recorded_at: %DateTime{} = at, throughput_source: src}
      when is_number(tps) ->
        age = short_age(at)
        rt = if is_number(d), do: " · #{d} ms RT", else: ""
        src_l = throughput_src_label(src)
        "#{tps} tok/s (#{src_l})#{rt} · #{age} ago"

      %{tokens_per_sec: tps} when is_number(tps) ->
        "#{tps} tok/s (probe)"

      _ ->
        "Run Pre-flight check to record tok/s for this model."
    end
  end

  defp throughput_src_label(:eval), do: "eval"
  defp throughput_src_label(:usage_wall_clock), do: "usage/wall"
  defp throughput_src_label(:none), do: "n/a"
  defp throughput_src_label(_), do: "?"

  defp short_age(%DateTime{} = at) do
    sec = DateTime.diff(DateTime.utc_now(), at, :second)

    cond do
      sec < 60 -> "#{sec}s"
      sec < 3600 -> "#{div(sec, 60)}m"
      true -> "#{div(sec, 3600)}h"
    end
  end

end
