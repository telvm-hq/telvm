defmodule SlackeelWeb.ModelsLive do
  @moduledoc """
  Manifest table; headroom/status live in the app nav (`Layouts.preflight_nav_strip/1`).
  Same `Slackeel.Preflight.snapshot/0` as Pre-flight.
  """
  use SlackeelWeb, :live_view

  alias Slackeel.Ollama.HotRegistry
  alias Slackeel.Preflight.DiskDuo

  @impl true
  def mount(_params, _session, socket) do
    socket =
      load(socket)
      |> assign(:metrics_live, false)
      |> assign(:highlight_ollama, nil)

    socket =
      if connected?(socket) do
        Phoenix.PubSub.subscribe(Slackeel.PubSub, Slackeel.Ollama.ProbeMetrics.pubsub_topic())
        Phoenix.PubSub.subscribe(Slackeel.PubSub, HotRegistry.pubsub_topic())
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

  def handle_info({:hot_models, snap}, socket) when is_map(snap) do
    socket =
      socket
      |> assign(:hot_snapshot, snap)
      |> assign(:disk_duo, DiskDuo.load())
      |> push_hot_phase_events(snap)

    {:noreply, socket}
  end

  @impl true
  def handle_event("hot_toggle", %{"tag" => tag}, socket) when is_binary(tag) do
    tag = String.trim(tag)

    row = Enum.find(socket.assigns.hot_snapshot.rows, &(&1.tag == tag))

    if row && row.want do
      HotRegistry.unwant(tag)
    else
      HotRegistry.want(tag)
    end

    {:noreply, socket}
  end

  defp load(socket) do
    metrics_live = Map.get(socket.assigns, :metrics_live, false)
    highlight_ollama = Map.get(socket.assigns, :highlight_ollama, nil)

    hot = HotRegistry.snapshot()
    disk = DiskDuo.load()

    case Slackeel.Preflight.snapshot() do
      {:ok, snap} ->
        assign(socket,
          page_title: "Models",
          top_bar_title: nil,
          error: nil,
          snapshot: snap,
          hot_snapshot: hot,
          disk_duo: disk,
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
          hot_snapshot: hot,
          disk_duo: disk,
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
    <div
      id="slac-models-live"
      phx-hook="HotModelPhase"
      class="telvm-terminal telvm-console-shell slac-tactical slac-preflight-view flex min-h-0 flex-1 flex-col gap-3 px-3 py-3 sm:px-4 sm:py-4"
    >
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

      <div
        :if={@snapshot}
        class="flex min-h-0 flex-1 flex-col gap-3 font-mono lg:flex-row lg:items-stretch lg:gap-3"
      >
        <section class="slac-card telvm-verify-card telvm-panel-border flex min-h-[min(46vh,26rem)] max-h-[min(56vh,32rem)] flex-col overflow-hidden border border-[color:var(--telvm-shell-border)] font-mono lg:min-h-0 lg:min-w-0 lg:max-h-none lg:w-[min(42%,22rem)] lg:max-w-md lg:flex-shrink-0 lg:self-stretch">
          <div class="slac-card__hdr flex shrink-0 !py-1.5 text-[9px] font-semibold uppercase tracking-[0.12em] text-[var(--telvm-shell-muted)]">
            <span>Inference (heuristic)</span>
          </div>

          <div class="slac-card__body flex min-h-0 flex-1 flex-col gap-2 overflow-hidden !pt-2 !pb-2 text-[10px] sm:text-xs">
            <div class="shrink-0">
              <div class="text-[11px] font-semibold tabular-nums text-[var(--telvm-shell-fg)] sm:text-xs">
                {format_gib(@hot_snapshot.used_bytes)} / {format_gib(@hot_snapshot.budget_bytes)} resident est.
              </div>
              <p class="telvm-muted-xs mt-1 text-[9px] leading-relaxed">
                Sum of manifest buffer margins for models Slackeel is loading or holding hot, compared to
                <code class="rounded px-0.5" style="background: var(--telvm-input-bg);">
                  :inference_memory_budget_gib
                </code>
                . This is not the disk headroom strip in the nav bar.
              </p>
              <div
                class="telvm-progress-track telvm-inference-capacity-track mt-2"
                title={"≈ #{inference_capacity_pct(@hot_snapshot)}% of heuristic budget reserved"}
              >
                <div
                  class="telvm-progress-fill"
                  style={"width: #{inference_capacity_pct(@hot_snapshot)}%;"}
                >
                </div>
              </div>
            </div>

            <div
              :if={inference_resident_tags_text(@hot_snapshot)}
              class="shrink-0 rounded-sm border border-[color:color-mix(in_oklch,var(--telvm-shell-border)_70%,transparent)] px-2 py-1.5 text-[9px] leading-snug text-[var(--telvm-shell-fg)]"
              style="background: color-mix(in oklch, var(--telvm-shell-elevated) 40%, transparent);"
            >
              <span class="font-semibold uppercase tracking-wide text-[var(--telvm-shell-muted)]">
                Resident
              </span>
              <span class="ml-1 font-mono">{inference_resident_tags_text(@hot_snapshot)}</span>
            </div>

            <div class="flex min-h-[10rem] flex-1 flex-col overflow-hidden border-t border-[color:var(--telvm-shell-border)] pt-2">
              <div class="shrink-0 pb-1 text-[9px] font-semibold uppercase tracking-[0.14em] text-[var(--telvm-shell-muted)]">
                Process updates
              </div>
              <div class="telvm-inference-activity-scroll min-h-0 flex-1 pr-0.5">
                <div
                  :if={inference_activity_empty?(@hot_snapshot)}
                  class="telvm-muted-xs py-3 text-[9px] leading-relaxed"
                >
                  No active pull, warm, or evict operations. Use
                  <span class="font-semibold text-[var(--telvm-shell-fg)]">Hot</span>
                  on a manifest row to stream weights from Ollama; live bytes and status lines appear here. Use
                  <span class="font-semibold text-[var(--telvm-shell-fg)]">Cv</span>
                  to unload a resident tag.
                </div>
                <div class="flex flex-col gap-3">
                  <div
                    :for={r <- inference_activity_rows(@hot_snapshot)}
                    data-hot-tag={r.tag}
                    class={[
                      "rounded-sm border px-2 py-2",
                      inference_activity_card_class(r)
                    ]}
                    style="border-color: color-mix(in oklch, var(--telvm-shell-border) 75%, transparent); background: color-mix(in oklch, var(--telvm-shell-elevated) 35%, transparent);"
                  >
                    <div class="flex flex-wrap items-baseline justify-between gap-x-2 gap-y-0.5">
                      <span class="font-mono text-[10px] font-semibold text-[var(--telvm-shell-fg)] sm:text-[11px]">
                        {r.tag}
                      </span>
                      <span class="text-[9px] font-semibold uppercase tracking-wide telvm-accent-text">
                        {inference_phase_badge(r)}
                      </span>
                    </div>
                    <p class="telvm-muted-xs mt-1 whitespace-pre-wrap text-[9px] leading-relaxed">
                      {inference_detail_paragraph(r)}
                    </p>
                    <div
                      :if={hot_show_load_bar?(@hot_snapshot, r.tag)}
                      class="mt-2 w-full"
                      title={hot_row_title(@hot_snapshot, r.tag)}
                    >
                      <div class="telvm-progress-track">
                        <div
                          data-hot-progress-fill
                          class={[
                            "telvm-progress-fill",
                            hot_load_fill_class(@hot_snapshot, r.tag)
                          ]}
                          style={hot_load_fill_style(@hot_snapshot, r.tag)}
                        >
                        </div>
                      </div>
                    </div>
                    <div :if={hot_show_unload_bar?(@hot_snapshot, r.tag)} class="mt-2 w-full">
                      <div
                        class="telvm-progress-track telvm-progress-track--unload"
                        title="Unloading…"
                      >
                        <div
                          data-hot-unload-fill
                          class="telvm-progress-fill telvm-progress-fill--unload-indeterminate"
                        >
                        </div>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>

            <div
              :if={@hot_snapshot.ollama_ps != []}
              class="shrink-0 border-t border-[color:var(--telvm-shell-border)] pt-2 text-[9px] text-[var(--telvm-shell-muted)]"
            >
              <span class="font-semibold uppercase tracking-wide text-[var(--telvm-shell-fg)]">
                Ollama ps
              </span>
              <span class="ml-1 font-mono text-[var(--telvm-shell-fg)]">
                {Enum.map_join(@hot_snapshot.ollama_ps, ", ", &ps_name/1)}
              </span>
            </div>
          </div>
        </section>

        <section class="slac-card slac-card--models-manifest telvm-verify-card telvm-panel-border flex min-h-0 min-w-0 flex-1 flex-col overflow-hidden border border-[color:var(--telvm-shell-border)] lg:flex-1">
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

                    <th class="py-1 px-0.5 text-center font-mono">Hot</th>

                    <th class="py-1 pl-0.5">OK</th>
                  </tr>
                </thead>

                <tbody>
                  <tr
                    :for={m <- @snapshot.models}
                    data-hot-tag={m.ollama}
                    class={[
                      "border-b border-[color:var(--telvm-shell-border)]/50",
                      if(m.enabled?, do: "", else: "opacity-55"),
                      @highlight_ollama == m.ollama && "telvm-models-row--metric-flash",
                      hot_row_class(@hot_snapshot, m.ollama)
                    ]}
                  >
                    <td class="max-w-[4rem] truncate py-1 pr-1 align-top sm:max-w-none">
                      {m.family}
                    </td>

                    <td class="py-1 px-0.5 font-mono align-top break-all">{m.ollama}</td>

                    <td class="whitespace-nowrap py-1 px-0.5 text-right font-mono">
                      {format_gib(m.approx_pull_bytes)}
                    </td>

                    <td class="whitespace-nowrap py-1 px-0.5 text-right font-mono">
                      {format_gib(m.margin_bytes)}
                    </td>

                    <td
                      class="max-w-[6rem] whitespace-nowrap py-1 px-0.5 text-right font-mono align-top text-[9px] sm:text-[10px]"
                      title={probe_metrics_title(@probe_metrics, m.ollama)}
                    >
                      {probe_tok_s(@probe_metrics, m.ollama)}
                    </td>

                    <td class="whitespace-nowrap py-1 px-0.5 text-center align-top">
                      <button
                        type="button"
                        phx-click="hot_toggle"
                        phx-value-tag={m.ollama}
                        title={hot_button_title(@hot_snapshot, m.ollama)}
                        class={[
                          "rounded-sm border px-1.5 py-0.5 text-[8px] font-bold uppercase tracking-wider",
                          hot_toggle_btn_class(@hot_snapshot, m.ollama)
                        ]}
                        style="border-color: var(--telvm-shell-border);"
                      >
                        {hot_toggle_label(@hot_snapshot, m.ollama)}
                      </button>
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
              Gate vs disk headroom · Hot/Cv only toggles intent; pull / warm / unload detail lives in Inference above.
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
      %{
        tokens_per_sec: tps,
        duration_ms: d,
        recorded_at: %DateTime{} = at,
        throughput_source: src
      }
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

  defp push_hot_phase_events(socket, snap) do
    Enum.reduce(snap.rows, socket, fn row, sk ->
      push_event(sk, "hot_model_phase", %{
        tag: row.tag,
        phase: hot_phase_event(row.status),
        load_pct: row.load_pct,
        unload_busy: row.unload_busy,
        ollama_status: row.load_status
      })
    end)
  end

  defp hot_phase_event(:ready), do: "ready"
  defp hot_phase_event(:pulling), do: "loading"
  defp hot_phase_event(:warming), do: "loading"
  defp hot_phase_event(:unloading), do: "evicting"
  defp hot_phase_event(:idle), do: "idle"
  defp hot_phase_event({:error, :over_budget}), do: "error"
  defp hot_phase_event({:error, _}), do: "error"
  defp hot_phase_event(_), do: "idle"

  defp ps_name(%{"name" => n}) when is_binary(n), do: n
  defp ps_name(%{name: n}) when is_binary(n), do: n
  defp ps_name(other), do: inspect(other, limit: 40)

  defp hot_row(snap, tag) do
    Enum.find(snap.rows, &(&1.tag == tag))
  end

  defp hot_row_class(snap, tag) do
    case hot_row(snap, tag) do
      %{status: :pulling} -> "telvm-hot-row--loading"
      %{status: :warming} -> "telvm-hot-row--loading"
      %{status: :unloading} -> "telvm-hot-row--evicting"
      %{status: {:error, _}} -> "telvm-hot-row--error"
      _ -> ""
    end
  end

  defp hot_toggle_btn_class(snap, tag) do
    case hot_row(snap, tag) do
      %{want: true, status: :ready} ->
        "telvm-accent-text"

      %{want: true} ->
        "text-[var(--telvm-shell-muted)]"

      _ ->
        "text-[var(--telvm-shell-fg)]"
    end
  end

  defp hot_toggle_label(snap, tag) do
    case hot_row(snap, tag) do
      %{want: true} -> "Cv"
      _ -> "Hot"
    end
  end

  defp hot_button_title(snap, tag) do
    case hot_row(snap, tag) do
      %{want: true, status: :ready} ->
        "Resident in Ollama. Cv evicts from the runner. Live detail: Inference → Process updates."

      %{want: true, status: s} when s in [:pulling, :warming, :unloading] ->
        "In progress—open Inference → Process updates for #{tag} (progress + Ollama status lines)."

      %{want: true, status: {:error, :over_budget}} ->
        "Over heuristic budget. See Inference → Process updates; Cv other hot models or raise :inference_memory_budget_gib."

      %{want: true, status: {:error, _}} ->
        "Load failed. See Inference → Process updates for the error card."

      %{want: false} ->
        "Hot: stream pull + warm + keep_alive. Progress and status appear under Inference."

      _ ->
        "Toggle hot load for this manifest tag."
    end
  end

  defp inference_capacity_pct(snap) when is_map(snap) do
    b = Map.get(snap, :budget_bytes)

    if is_integer(b) and b > 0 do
      min(100, round(Map.get(snap, :used_bytes, 0) * 100 / b))
    else
      0
    end
  end

  defp inference_resident_tags_text(snap) when is_map(snap) do
    snap.rows
    |> Enum.filter(fn r -> r.want && r.status == :ready end)
    |> Enum.map(& &1.tag)
    |> case do
      [] -> nil
      xs -> Enum.join(xs, ", ")
    end
  end

  defp inference_activity_empty?(snap), do: inference_activity_rows(snap) == []

  defp inference_activity_rows(snap) when is_map(snap) do
    snap.rows
    |> Enum.filter(fn r ->
      match?({:error, _}, r.status) or (r.want && r.status in [:pulling, :warming, :unloading])
    end)
    |> Enum.sort_by(fn r -> {inference_activity_sort(r.status), r.tag} end)
  end

  defp inference_activity_sort(:pulling), do: 0
  defp inference_activity_sort(:warming), do: 1
  defp inference_activity_sort(:unloading), do: 2
  defp inference_activity_sort({:error, _}), do: 3
  defp inference_activity_sort(_), do: 9

  defp inference_phase_badge(r) when is_map(r) do
    case r.status do
      :pulling -> "Pull"
      :warming -> "Warm"
      :unloading -> "Evict"
      {:error, :over_budget} -> "Budget"
      {:error, _} -> "Error"
      _ -> "?"
    end
  end

  defp inference_activity_card_class(r) when is_map(r) do
    case r.status do
      {:error, _} -> "telvm-inference-card--err"
      :unloading -> "telvm-inference-card--evict"
      _ -> ""
    end
  end

  defp inference_detail_paragraph(r) when is_map(r) do
    ls = Map.get(r, :load_status)

    ollama_line =
      if is_binary(ls) and String.trim(ls) != "" do
        "\n\nLast Ollama status: " <> ls
      else
        ""
      end

    base =
      case r.status do
        :pulling ->
          "Slackeel is streaming the model pull from your Ollama host. When the API reports completed and total bytes, the bar advances; otherwise you may see an indeterminate sweep while the registry waits on manifest, blob download, or verification (normal for large blobs)."

        :warming ->
          "Weights are on disk. Slackeel warms the runner with a tiny generate and long keep_alive so the model stays ready for chat without a cold load on first token."

        :unloading ->
          "Slackeel issued an unload (keep_alive 0) so Ollama can evict this tag from the active runner. The sweep bar reflects the unload request; the card clears when the registry finishes."

        {:error, :over_budget} ->
          "Keeping this tag hot would exceed :inference_memory_budget_gib once margins for all in-flight and resident models are summed. Cv another resident model or raise the heuristic budget in config if your machine allows."

        {:error, reason} ->
          "The Slackeel load pipeline stopped with: " <> inspect(reason, limit: 200)

        _ ->
          ""
      end

    String.trim(base <> ollama_line)
  end

  defp hot_show_load_bar?(snap, tag) do
    case hot_row(snap, tag) do
      %{want: true, status: s} when s in [:pulling, :warming] -> true
      _ -> false
    end
  end

  defp hot_show_unload_bar?(snap, tag) do
    case hot_row(snap, tag) do
      %{unload_busy: true} -> true
      _ -> false
    end
  end

  defp hot_row_title(snap, tag) do
    case hot_row(snap, tag) do
      %{load_status: s} when is_binary(s) -> s
      _ -> ""
    end
  end

  defp hot_load_fill_class(snap, tag) do
    case hot_row(snap, tag) do
      %{load_pct: p} when is_integer(p) -> ""
      _ -> "telvm-progress-fill--indeterminate"
    end
  end

  defp hot_load_fill_style(snap, tag) do
    case hot_row(snap, tag) do
      %{load_pct: p} when is_integer(p) -> "width: #{p}%;"
      _ -> "width: 32%;"
    end
  end
end
