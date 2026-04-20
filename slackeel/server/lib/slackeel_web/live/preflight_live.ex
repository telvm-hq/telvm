defmodule SlackeelWeb.PreflightLive do
  use SlackeelWeb, :live_view

  alias Slackeel.Ollama.VerifyPipeline

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:verify_running, false)
      |> assign(:verify_results, %{})
      |> assign(:verify_started_at, nil)
      |> assign(:verify_cancel_agent, nil)
      |> assign(:show_ollama_hud, true)
      |> assign(:main_view_tab, :mission)
      |> assign_probe_defaults()

    {:ok, load(socket)}
  end

  @impl true
  def handle_event("set_main_view_tab", %{"tab" => "chat"}, socket) do
    {:noreply, assign(socket, :main_view_tab, :chat)}
  end

  def handle_event("set_main_view_tab", %{"tab" => "mission"}, socket) do
    {:noreply, assign(socket, :main_view_tab, :mission)}
  end

  def handle_event("set_main_view_tab", _, socket) do
    {:noreply, socket}
  end

  def handle_event("set_probe_prompt", params, socket) do
    if socket.assigns[:verify_running] do
      {:noreply, socket}
    else
      draft =
        Map.get(params, "prompt_draft") ||
          Map.get(params, "prompt") ||
          Map.get(params, "value") ||
          ""

      locked =
        case socket.assigns[:probe_prompt_locked] do
          l when is_binary(l) -> l
          _ -> Slackeel.Ollama.Config.integration_verify_prompt()
        end

      needs_commit = String.trim(draft) != String.trim(locked)

      {:noreply,
       socket
       |> assign(:probe_prompt_draft, draft)
       |> assign(:probe_prompt_needs_commit, needs_commit)}
    end
  end

  def handle_event("commit_probe_prompt", _params, socket) do
    cond do
      socket.assigns[:verify_running] ->
        {:noreply, socket}

      true ->
        locked =
          socket.assigns[:probe_prompt_draft]
          |> to_string()
          |> String.trim()

        if locked == "" do
          {:noreply, put_flash(socket, :error, "Probe prompt cannot be empty.")}
        else
          {:noreply,
           socket
           |> assign(:probe_prompt_locked, locked)
           |> assign(:probe_prompt_draft, locked)
           |> assign(:probe_prompt_needs_commit, false)
           |> put_flash(:info, "Probe locked — check will send: #{short_probe_hint(locked)}")}
        end
    end
  end

  def handle_event("verify_cancel", _params, socket) do
    if socket.assigns[:verify_running] do
      case socket.assigns[:verify_cancel_agent] do
        pid when is_pid(pid) ->
          _ = Agent.update(pid, fn _ -> %{stop: true} end)

        _ ->
          :ok
      end
    end

    {:noreply, socket}
  end

  def handle_event("verify_integration", _params, socket) do
    cond do
      socket.assigns.verify_running ->
        {:noreply, socket}

      socket.assigns[:snapshot] == nil ->
        {:noreply, put_flash(socket, :error, "Load pre-flight metrics first.")}

      socket.assigns[:probe_prompt_needs_commit] ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Press lock first — your edits are not armed for the run yet."
         )}

      String.trim(to_string(socket.assigns[:probe_prompt_locked] || "")) == "" ->
        {:noreply,
         put_flash(socket, :error, "Lock a non-empty probe prompt before running verify.")}

      true ->
        models = socket.assigns.snapshot.models |> Enum.map(& &1.ollama) |> Enum.uniq()
        retries = Application.get_env(:slackeel, :integration_verify_retries) || 3
        probe_prompt = socket.assigns[:probe_prompt_locked] |> to_string() |> String.trim()

        pending =
          for m <- models,
              into: %{},
              do: {m, initial_verify_row()}

        parent = self()
        on_event = fn {:notify, msg} -> send(parent, {:verify_event, msg}) end

        {cancel_agent, should_continue} =
          if models == [] do
            {nil, fn -> true end}
          else
            {:ok, agent} = Agent.start_link(fn -> %{stop: false} end)

            cont = fn ->
              Agent.get(agent, fn %{stop: s} -> not s end)
            end

            {agent, cont}
          end

        Task.start(fn ->
          if models == [] do
            send(parent, :verify_complete)
          else
            _ =
              VerifyPipeline.run(models,
                mode: :serial,
                pull: true,
                unload: true,
                retries: retries,
                verbose: false,
                on_event: on_event,
                should_continue: should_continue,
                probe_prompt: probe_prompt
              )

            send(parent, :verify_complete)
          end
        end)

        started_at = DateTime.utc_now()

        {:noreply,
         socket
         |> assign(:verify_running, true)
         |> assign(:verify_cancel_agent, cancel_agent)
         |> assign(:verify_results, pending)
         |> assign(:verify_started_at, started_at)}
    end
  end

  defp initial_verify_row do
    %{
      overall: :waiting,
      pull: :none,
      probe: :none,
      unload: :none,
      reply: nil,
      error: nil,
      probe_metrics: nil
    }
  end

  defp assign_probe_defaults(socket) do
    p = Slackeel.Ollama.Config.integration_verify_prompt()

    assign(socket,
      probe_prompt_draft: p,
      probe_prompt_locked: p,
      probe_prompt_needs_commit: false
    )
  end

  defp short_probe_hint(s) when is_binary(s) do
    t = String.trim(s)

    if String.length(t) <= 48 do
      t
    else
      String.slice(t, 0, 45) <> "…"
    end
  end

  @impl true
  def handle_info({:verify_event, {model, :cycle, :started}}, socket) do
    results = socket.assigns.verify_results

    row =
      results
      |> Map.get(model, initial_verify_row())
      |> Map.merge(%{overall: :in_progress, pull: :none, probe: :none, unload: :none, error: nil})

    {:noreply, assign(socket, :verify_results, Map.put(results, model, row))}
  end

  def handle_info({:verify_event, {model, :pull, :started}}, socket) do
    {:noreply, update_phase(socket, model, :pull, :running)}
  end

  def handle_info({:verify_event, {model, :pull, :ok}}, socket) do
    {:noreply, update_phase(socket, model, :pull, :ok)}
  end

  def handle_info({:verify_event, {model, :pull, {:error, e}}}, socket) do
    socket =
      socket
      |> update_phase(model, :pull, :error)
      |> put_verify_error(model, format_verify_error(e))
      |> mark_overall(model, :error)

    {:noreply, socket}
  end

  def handle_info({:verify_event, {model, :probe, :started}}, socket) do
    {:noreply, update_phase(socket, model, :probe, :running)}
  end

  def handle_info({:verify_event, {model, :probe, {:ok, text, meta}}}, socket) do
    _ = Slackeel.Ollama.ProbeMetrics.record(model, meta)

    results = socket.assigns.verify_results

    row =
      results
      |> Map.get(model, initial_verify_row())
      |> Map.merge(%{probe: :ok, reply: text, error: nil, probe_metrics: meta})

    {:noreply, assign(socket, :verify_results, Map.put(results, model, row))}
  end

  def handle_info({:verify_event, {model, :probe, {:error, e}}}, socket) do
    socket =
      socket
      |> update_phase(model, :probe, :error)
      |> put_verify_error(model, format_verify_error(e))
      |> mark_overall(model, :error)

    {:noreply, socket}
  end

  def handle_info({:verify_event, {model, :unload, :started}}, socket) do
    {:noreply, update_phase(socket, model, :unload, :running)}
  end

  def handle_info({:verify_event, {model, :unload, :ok}}, socket) do
    {:noreply, update_phase(socket, model, :unload, :ok)}
  end

  def handle_info({:verify_event, {model, :unload, {:error, e}}}, socket) do
    results = socket.assigns.verify_results

    row =
      results
      |> Map.get(model, initial_verify_row())
      |> Map.merge(%{unload: :error, error: "Unload: " <> format_verify_error(e)})

    {:noreply, assign(socket, :verify_results, Map.put(results, model, row))}
  end

  def handle_info({:verify_event, {model, :cycle, :done, {:ok, _, _}}}, socket) do
    results = socket.assigns.verify_results

    row =
      results
      |> Map.get(model, initial_verify_row())
      |> Map.merge(%{overall: :done_ok, error: nil})

    {:noreply, assign(socket, :verify_results, Map.put(results, model, row))}
  end

  def handle_info({:verify_event, {model, :cycle, :done, {:error, _}}}, socket) do
    {:noreply, mark_overall(socket, model, :error)}
  end

  def handle_info({:verify_event, {:log, _line}}, socket) do
    {:noreply, socket}
  end

  def handle_info(:verify_complete, socket) do
    socket =
      socket
      |> stop_verify_cancel_agent()
      |> assign(:verify_running, false)
      |> assign(:verify_started_at, nil)
      |> assign(:verify_cancel_agent, nil)

    {:noreply, socket}
  end

  defp stop_verify_cancel_agent(socket) do
    case socket.assigns[:verify_cancel_agent] do
      pid when is_pid(pid) ->
        _ = Agent.stop(pid, :normal)
        socket

      _ ->
        socket
    end
  end

  defp update_phase(socket, model, phase, value) do
    results = socket.assigns.verify_results

    row =
      results
      |> Map.get(model, initial_verify_row())
      |> Map.put(phase, value)

    assign(socket, :verify_results, Map.put(results, model, row))
  end

  defp put_verify_error(socket, model, message) do
    results = socket.assigns.verify_results

    row =
      results
      |> Map.get(model, initial_verify_row())
      |> Map.put(:error, message)

    assign(socket, :verify_results, Map.put(results, model, row))
  end

  defp mark_overall(socket, model, :error) do
    results = socket.assigns.verify_results

    row =
      results
      |> Map.get(model, initial_verify_row())
      |> Map.put(:overall, :done_error)

    assign(socket, :verify_results, Map.put(results, model, row))
  end

  defp format_verify_error({:pull, e}), do: "Pull: " <> format_verify_error(e)
  defp format_verify_error({:http, s, b}), do: "HTTP #{s}: #{inspect(b, limit: 200)}"
  defp format_verify_error({:api, e}), do: "API: #{inspect(e, limit: 200)}"
  defp format_verify_error({:bad_shape, m}), do: "Unexpected response shape: #{inspect(m, limit: 200)}"
  defp format_verify_error({:pull_response, o}), do: "Pull: #{inspect(o, limit: 120)}"
  defp format_verify_error(e) when is_binary(e), do: e
  defp format_verify_error(e), do: inspect(e, limit: 500)

  defp load(socket) do
    vr = socket.assigns[:verify_results] || %{}
    vw = socket.assigns[:verify_running] || false
    vst = socket.assigns[:verify_started_at]

    main_view_tab = Map.get(socket.assigns, :main_view_tab, :mission)
    vca = socket.assigns[:verify_cancel_agent]

    default_p = Slackeel.Ollama.Config.integration_verify_prompt()

    draft =
      case Map.get(socket.assigns, :probe_prompt_draft) do
        d when is_binary(d) -> d
        _ -> default_p
      end

    locked =
      case Map.get(socket.assigns, :probe_prompt_locked) do
        l when is_binary(l) -> l
        _ -> default_p
      end

    needs_commit = String.trim(draft) != String.trim(locked)

    case Slackeel.Preflight.snapshot() do
      {:ok, snap} ->
        assign(socket,
          page_title: "Pre-flight",
          top_bar_title: "PRE-FLIGHT",
          error: nil,
          snapshot: snap,
          refreshed_at: DateTime.utc_now(),
          verify_results: vr,
          verify_running: vw,
          verify_started_at: vst,
          verify_cancel_agent: vca,
          show_ollama_hud: true,
          main_view_tab: main_view_tab,
          probe_prompt_draft: draft,
          probe_prompt_locked: locked,
          probe_prompt_needs_commit: needs_commit
        )

      {:error, reason} ->
        assign(socket,
          page_title: "Pre-flight",
          top_bar_title: "PRE-FLIGHT",
          error: inspect(reason),
          snapshot: nil,
          refreshed_at: DateTime.utc_now(),
          verify_results: vr,
          verify_running: vw,
          verify_started_at: vst,
          verify_cancel_agent: vca,
          show_ollama_hud: true,
          main_view_tab: main_view_tab,
          probe_prompt_draft: draft,
          probe_prompt_locked: locked,
          probe_prompt_needs_commit: needs_commit
        )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell slac-tactical slac-preflight-view flex min-h-0 flex-1 flex-col gap-3 px-3 py-3 sm:px-4 sm:py-4">
      <div :if={@error} class="shrink-0 rounded-sm border px-2 py-1 text-[11px] telvm-text-danger-ink font-mono"
        style="border-color: var(--telvm-danger-border); background: var(--telvm-danger-bg);"
      >
        METRICS FAIL — {@error}
      </div>

      <div :if={@snapshot} class="flex min-h-0 flex-1 flex-col gap-2 font-mono">
        <section class="telvm-panel-border telvm-panel-bg flex min-h-0 flex-1 flex-col overflow-hidden rounded-sm border">
          <div class="flex min-h-0 flex-1 flex-col gap-2 overflow-hidden p-2 pt-2 sm:p-3">
            <div class="flex shrink-0 flex-wrap items-center justify-between gap-2">
              <span class="text-[10px] uppercase tracking-[0.14em] text-[var(--telvm-shell-muted)]">
                view
              </span>
              <div
                class="inline-flex overflow-hidden rounded border text-[10px]"
                role="tablist"
                aria-label="Pre-flight view"
                style="border-color: var(--telvm-shell-border);"
              >
                <button
                  type="button"
                  role="tab"
                  phx-click="set_main_view_tab"
                  phx-value-tab="mission"
                  aria-selected={@main_view_tab == :mission}
                  class={preflight_main_tab_btn_class(@main_view_tab == :mission)}
                >
                  mission
                </button>
                <button
                  type="button"
                  role="tab"
                  phx-click="set_main_view_tab"
                  phx-value-tab="chat"
                  aria-selected={@main_view_tab == :chat}
                  class={preflight_main_tab_btn_class(@main_view_tab == :chat)}
                >
                  transcript
                </button>
              </div>
            </div>

            <div
              :if={@main_view_tab == :mission}
              class="flex min-h-0 flex-1 flex-col gap-2 overflow-hidden"
            >
              <div
                id="preflight-mission-board"
                phx-hook="MissionBoard"
                class="telvm-mission-board flex min-h-0 flex-1 flex-col overflow-hidden"
              >
                <div class="telvm-mission-board__hdr shrink-0">
                  <span>Model</span>
                  <span class="telvm-mission-phase" title="Pull weights (local)">P</span>
                  <span class="telvm-mission-phase" title="Probe phase (OK = request finished)">C</span>
                  <span class="telvm-mission-phase" title="Unload from VRAM">U</span>
                  <span class="text-right">Sync</span>
                </div>
                <div class="telvm-mission-board__scroll">
                  <div
                    :for={{m, idx, r} <- mission_rows(@snapshot.models, @verify_results)}
                    id={"mission-row-#{idx}"}
                    class={mission_row_classes(r)}
                  >
                    <div class="telvm-mission-model" title={m.ollama}>{m.ollama}</div>
                    <div class="telvm-mission-phase">
                      <span class={phase_pill_class(r.pull)}>{phase_label(r.pull)}</span>
                    </div>
                    <div class="telvm-mission-phase">
                      <span class={phase_pill_class(r.probe)}>{phase_label(r.probe)}</span>
                    </div>
                    <div class="telvm-mission-phase">
                      <span class={phase_pill_class(r.unload)}>{phase_label(r.unload)}</span>
                    </div>
                    <div class="flex justify-end">
                      <span :if={r.overall == :standby} class={overall_pill_class(:standby)}>STBY</span>
                      <span :if={r.overall == :waiting} class={overall_pill_class(:waiting)}>Q</span>
                      <span :if={r.overall == :in_progress} class={overall_pill_class(:in_progress)}>…</span>
                      <span :if={r.overall == :done_ok} class={overall_pill_class(:done_ok)}>OK</span>
                      <span :if={r.overall == :done_error} class={overall_pill_class(:done_error)}>X</span>
                    </div>
                  </div>
                </div>
              </div>

              <div
                class="shrink-0 rounded-sm border border-[color:var(--telvm-shell-border)] px-2 py-1.5 text-[10px] telvm-panel-border"
                style="background: var(--telvm-input-bg);"
              >
                <p class="telvm-muted-xs uppercase tracking-wide">armed probe</p>
                <p class="mt-1 text-[8px] leading-snug text-[var(--telvm-shell-muted)]">
                  Edit and lock in the verify bar above — check always sends this text.
                </p>
                <pre
                  class="telvm-accent-ring mt-1 max-h-24 overflow-y-auto whitespace-pre-wrap break-words rounded-sm border px-2 py-1 font-mono text-[10px] leading-snug"
                  style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-shell-bg) 55%, transparent); color: var(--telvm-shell-fg);"
                  title={@probe_prompt_locked}
                >{@probe_prompt_locked}</pre>
              </div>

              <p class="shrink-0 text-[9px] leading-snug text-[var(--telvm-shell-muted)]">
                Full prompt + answers:
                <button
                  type="button"
                  phx-click="set_main_view_tab"
                  phx-value-tab="chat"
                  class="font-semibold text-[var(--telvm-shell-fg)] underline decoration-[color-mix(in_oklch,var(--telvm-accent)_55%,transparent)] underline-offset-2 hover:opacity-90"
                >
                  transcript
                </button>
              </p>
            </div>

            <div
              :if={@main_view_tab == :chat}
              class="telvm-preflight-chat-root flex min-h-0 flex-1 flex-col gap-2 overflow-hidden"
            >
              <div
                id="preflight-chat-feed"
                phx-hook="ScrollProbeLog"
                class="telvm-chat-feed flex min-h-0 flex-1 flex-col overflow-hidden rounded-sm border border-[color:var(--telvm-shell-border)]"
                style="background: color-mix(in oklch, var(--telvm-input-bg) 55%, transparent);"
              >
                <p class="shrink-0 border-b border-[color:var(--telvm-shell-border)] px-2 py-1 text-[9px] leading-snug text-[var(--telvm-shell-muted)]">
                  Serial probe — same prompt per model, one block per model.
                </p>
                <div class="shrink-0 border-b border-[color:var(--telvm-shell-border)] px-2 py-2" style="background: color-mix(in oklch, var(--telvm-shell-elevated) 25%, transparent);">
                  <span class="text-[9px] text-[var(--telvm-shell-muted)]">
                    # in · probe is set in the verify bar — same text per model below
                  </span>
                </div>
                <div data-probe-log-scroll class="min-h-0 flex-1 overflow-y-auto px-2 py-2">
                  <div :for={m <- @snapshot.models} class="border-b border-[color:var(--telvm-shell-border)] py-2.5 last:border-b-0">
                    <div class="text-[10px] telvm-accent-text break-all">{m.ollama}</div>
                    <div class="mt-1.5 space-y-2 border-l-2 pl-2 telvm-prose-bar">
                      <div>
                        <span class="text-[9px] text-[var(--telvm-shell-muted)]"># out</span>
                        <% r = verify_row_for(@verify_results, m.ollama) %>
                        <%= case assistant_chat_segment(r) do %>
                          <% {:reply, text} -> %>
                            <pre class="mt-0.5 max-h-40 overflow-y-auto whitespace-pre-wrap rounded-sm border border-[color:var(--telvm-shell-border)] bg-[color-mix(in_oklch,var(--telvm-shell-bg)_40%,transparent)] p-1.5 text-[10px] leading-relaxed sm:max-h-52">{text}</pre>
                          <% {:error, msg} -> %>
                            <p class="telvm-text-danger-ink mt-0.5 whitespace-pre-wrap break-words text-[10px] leading-relaxed">
                              {msg}
                            </p>
                          <% {:idle, hint} -> %>
                            <p class="mt-0.5 text-[10px] leading-relaxed text-[var(--telvm-shell-muted)]">
                              {hint}
                            </p>
                        <% end %>
                      </div>
                    </div>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </section>
      </div>

      <div
        :if={@snapshot && (agent_disk_volumes(@snapshot) != [] || (@snapshot.disks && @snapshot.disks != []))}
        class="slac-preflight-disk-grid mt-1 shrink-0 space-y-1.5"
      >
        <p class="text-center text-[9px] uppercase tracking-wider text-[var(--telvm-shell-muted)]">Host</p>
        <div class="slac-grid">
          <section
            :if={agent_disk_volumes(@snapshot) != []}
            class="slac-card slac-card--square telvm-verify-card telvm-panel-border"
          >
            <div class="slac-card__hdr">Agent disk</div>
            <div class="slac-card__body">
              <p :if={agent_disk_note(@snapshot) != ""} class="telvm-muted-xs mb-2 leading-snug">
                {agent_disk_note(@snapshot)}
              </p>
              <div class="min-w-0 overflow-x-auto">
                <table class="w-full text-left text-[10px] sm:text-xs font-mono">
                  <thead>
                    <tr class="border-b border-[color:var(--telvm-shell-border)]">
                      <th class="py-1 pr-1 font-medium text-[var(--telvm-shell-muted)]">Vol</th>
                      <th class="py-1 px-0.5 text-right">Free</th>
                      <th class="py-1 px-0.5 text-right">Used</th>
                      <th class="py-1 pl-0.5 text-right">Cap</th>
                    </tr>
                  </thead>
                  <tbody>
                    <tr
                      :for={v <- agent_disk_volumes(@snapshot)}
                      class="border-b border-[color:var(--telvm-shell-border)]/50"
                    >
                      <td class="py-1 pr-1 align-top">{v["name"]}{root_label(v["root"])}</td>
                      <td class="py-1 px-0.5 text-right whitespace-nowrap">{format_gib(coerce_bytes(v["free_bytes"]))}</td>
                      <td class="py-1 px-0.5 text-right whitespace-nowrap">{format_gib(coerce_bytes(v["used_bytes"]))}</td>
                      <td class="py-1 pl-0.5 text-right whitespace-nowrap">{format_gib(coerce_bytes(v["capacity_bytes"]))}</td>
                    </tr>
                  </tbody>
                </table>
              </div>
            </div>
          </section>

          <section
            :if={@snapshot.disks && @snapshot.disks != []}
            class="slac-card slac-card--square telvm-verify-card telvm-panel-border"
          >
            <div class="slac-card__hdr">Beam disks</div>
            <div class="slac-card__body min-w-0 overflow-x-auto">
              <table class="w-full text-left text-[10px] sm:text-xs font-mono">
                <thead>
                  <tr class="border-b border-[color:var(--telvm-shell-border)]">
                    <th class="py-1 pr-1">ID</th>
                    <th class="py-1 px-0.5 text-right">Avail</th>
                    <th class="py-1 pl-0.5 text-right">Cap</th>
                  </tr>
                </thead>
                <tbody>
                  <tr
                    :for={d <- @snapshot.disks}
                    class="border-b border-[color:var(--telvm-shell-border)]/50"
                  >
                    <td class="py-1 pr-1">{d.id}</td>
                    <td class="py-1 px-0.5 text-right">{format_gib_kb(d.available_kb)}</td>
                    <td class="py-1 pl-0.5 text-right">{format_gib_kb(d.capacity_kb)}</td>
                  </tr>
                </tbody>
              </table>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp preflight_main_tab_btn_class(true),
    do:
      "px-3 py-1.5 font-semibold uppercase tracking-wide telvm-btn-primary border-0 rounded-none first:rounded-l last:rounded-r outline-none focus-visible:ring-1 focus-visible:ring-offset-0"

  defp preflight_main_tab_btn_class(false),
    do:
      "px-3 py-1.5 font-semibold uppercase tracking-wide rounded-none first:rounded-l last:rounded-r border-0 bg-[color-mix(in_oklch,var(--telvm-shell-bg)_40%,transparent)] text-[var(--telvm-shell-muted)] hover:text-[var(--telvm-shell-fg)] outline-none focus-visible:ring-1"

  defp verify_row_for(results, ollama) when is_map(results) and is_binary(ollama) do
    Map.get(results, ollama, %{
      overall: :standby,
      pull: :none,
      probe: :none,
      unload: :none,
      reply: nil,
      error: nil
    })
  end

  defp mission_rows(models, results) when is_list(models) do
    models
    |> Enum.with_index()
    |> Enum.map(fn {m, idx} -> {m, idx, verify_row_for(results, m.ollama)} end)
  end

  defp mission_row_classes(%{overall: :in_progress}),
    do: "telvm-mission-row telvm-mission-row--current"

  defp mission_row_classes(_), do: "telvm-mission-row"

  defp phase_label(:none), do: "—"
  defp phase_label(:running), do: "…"
  defp phase_label(:ok), do: "OK"
  defp phase_label(:error), do: "Err"
  defp phase_label(_), do: "—"

  defp overall_pill_class(:standby),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] font-medium telvm-muted-xs telvm-pill-neutral"

  defp overall_pill_class(:waiting),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] font-medium telvm-muted-xs telvm-pill-neutral"

  defp overall_pill_class(:in_progress),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] font-medium telvm-accent-text telvm-pill-accent"

  defp overall_pill_class(:done_ok),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] font-medium telvm-text-ok telvm-pill-ok"

  defp overall_pill_class(:done_error),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] font-medium telvm-text-danger-ink telvm-pill-bad"

  defp overall_pill_class(_),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] font-medium telvm-muted-xs"

  defp phase_pill_class(:none),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] telvm-muted-xs telvm-pill-neutral"

  defp phase_pill_class(:running),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] telvm-accent-text telvm-pill-accent"

  defp phase_pill_class(:ok),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] telvm-text-ok telvm-pill-ok"

  defp phase_pill_class(:error),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] telvm-text-danger-ink telvm-pill-bad"

  defp phase_pill_class(_),
    do: "inline-flex rounded px-2 py-0.5 text-[10px] telvm-muted-xs"

  defp assistant_chat_segment(row) do
    err = Map.get(row, :error)
    reply = Map.get(row, :reply)

    cond do
      is_binary(err) and String.trim(err) != "" ->
        {:error, err}

      is_binary(reply) and String.trim(reply) != "" ->
        {:reply, reply}

      row.overall == :done_ok ->
        {:idle, "Probe finished — no assistant text returned."}

      row.overall == :done_error ->
        {:error, if(is_binary(err) and String.trim(err) != "", do: err, else: "Run failed.")}

      row.overall == :in_progress and row.probe == :running ->
        {:idle, "Awaiting assistant reply…"}

      row.overall == :in_progress and row.pull == :running ->
        {:idle, "Pulling model weights…"}

      row.overall == :in_progress ->
        {:idle, "In progress…"}

      row.overall == :waiting ->
        {:idle, "Queued for this run."}

      row.overall == :standby ->
        {:idle, "Not probed yet — run Check models above."}

      true ->
        {:idle, "—"}
    end
  end

  defp agent_disk_volumes(%{remote_raw: %{"disk" => %{"volumes" => v}}}) when is_list(v), do: v
  defp agent_disk_volumes(_), do: []

  defp agent_disk_note(%{remote_raw: %{"disk" => %{"note" => n}}}) when is_binary(n), do: n
  defp agent_disk_note(_), do: ""

  defp root_label(r) when is_binary(r) and r != "", do: " (#{r})"
  defp root_label(_), do: ""

  defp coerce_bytes(v) when is_integer(v), do: v
  defp coerce_bytes(v) when is_float(v), do: trunc(v)
  defp coerce_bytes(_), do: 0

  defp format_gib(bytes) when is_integer(bytes) do
    g = bytes / 1_073_741_824
    :erlang.float_to_binary(g, decimals: 2) <> " GiB"
  end

  defp format_gib_kb(kb) when is_integer(kb) do
    format_gib(kb * 1024)
  end
end
