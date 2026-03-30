defmodule CompanionWeb.StatusLive do
  use CompanionWeb, :live_view

  alias Companion.Preflight
  alias Companion.StackStatus
  alias Companion.VmLifecycle
  alias Companion.VmLifecycle.Runner
  alias Companion.VmLifecycle.SoakRunner
  alias Companion.LabCatalog
  alias Companion.LabImageBuilder

  @default_entry LabCatalog.get(:stock_node)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:host_diagram, StackStatus.host_diagram_string())
      |> assign(:report, Preflight.run())
      |> assign(:page_title, page_title(socket))
      |> assign(:vm_preflight_log, [])
      |> assign(:vm_preflight_busy, false)
      |> assign(:vm_preflight_result, nil)
      |> assign(:lab_catalog, LabCatalog.with_availability())
      |> assign(:image_build_log, [])
      |> assign(:image_build_busy, false)
      |> assign(:image_pull_busy, false)
      |> assign(:selected_image, @default_entry.ref)
      |> assign(:selected_use_image_cmd, @default_entry.use_image_cmd)
      |> assign(:selected_container_cmd, @default_entry.container_cmd)
      |> assign(:selected_catalog_id, @default_entry.id)
      |> assign(:destroying, false)
      |> assign(:warm_machines, [])
      |> assign(:soak_busy, false)
      |> assign(:soak_session, nil)
      |> assign(:preflight_session, nil)
      |> assign(:lab_readiness, %{})

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Companion.PubSub, Preflight.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, VmLifecycle.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, LabImageBuilder.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, SoakRunner.topic())
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    case socket.assigns.live_action do
      redirect when redirect in [:legacy_certificate_redirect, :legacy_images_redirect, :legacy_preflight_redirect] ->
        {:noreply, push_navigate(socket, to: ~p"/machines", replace: true)}

      :machines ->
        socket = assign(socket, :page_title, page_title(socket))
        socket = assign(socket, :warm_machines, fetch_warm_machines())
        if connected?(socket), do: schedule_warm_refresh()
        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, :page_title, page_title(socket))}
    end
  end

  defp page_title(socket) do
    case socket.assigns[:live_action] do
      :topology -> "Topology"
      :machines -> "Machines"
      _ -> "Pre-flight"
    end
  end

  # --- PubSub handlers ---

  @impl true
  def handle_info({:report, report}, socket) do
    {:noreply, assign(socket, :report, report)}
  end

  def handle_info({:vm_manager_preflight, {:line, kind, ts, text}}, socket) do
    if socket.assigns.live_action == :machines || socket.assigns[:vm_preflight_busy] do
      log = socket.assigns[:vm_preflight_log] || []
      log = log ++ [{kind, ts, text}]
      log = Enum.take(log, -400)
      {:noreply, assign(socket, :vm_preflight_log, log)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:vm_manager_preflight, {:session, :clear}}, socket) do
    {:noreply, assign(socket, :preflight_session, nil)}
  end

  def handle_info({:vm_manager_preflight, {:session, %{container_id: _, phase: _} = data}}, socket) do
    {:noreply, assign(socket, :preflight_session, data)}
  end

  def handle_info({:vm_manager_preflight, {:done, result}}, socket) do
    {:noreply,
     socket
     |> assign(vm_preflight_busy: false, vm_preflight_result: result)
     |> assign(:preflight_session, nil)}
  end

  def handle_info({:lab_image_build, {:line, ts, text}}, socket) do
    log = socket.assigns[:image_build_log] || []
    log = log ++ [{ts, text}]
    log = Enum.take(log, -200)
    {:noreply, assign(socket, :image_build_log, log)}
  end

  def handle_info({:lab_image_build, {:done, _result}}, socket) do
    {:noreply, assign(socket, :image_build_busy, false)}
  end

  def handle_info({:image_pull_done, _ref, result}, socket) do
    socket =
      socket
      |> assign(:image_pull_busy, false)
      |> assign(:lab_catalog, LabCatalog.with_availability())

    socket =
      case result do
        :ok -> put_flash(socket, :info, "Image pulled successfully.")
        {:error, reason} -> put_flash(socket, :error, "Pull failed: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_info({:soak_monitor, {:session, :clear}}, socket) do
    {:noreply, assign(socket, :soak_session, nil)}
  end

  def handle_info({:soak_monitor, {:session, %{container_id: _, phase: _} = data}}, socket) do
    {:noreply, assign(socket, :soak_session, data)}
  end

  def handle_info({:soak_monitor, {:line, kind, ts, text}}, socket) do
    if socket.assigns.live_action == :machines || socket.assigns[:soak_busy] do
      log = socket.assigns[:vm_preflight_log] || []
      log = log ++ [{kind, ts, text}]
      log = Enum.take(log, -400)
      {:noreply, assign(socket, :vm_preflight_log, log)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:soak_monitor, {:done, result, meta}}, socket) when is_map(meta) do
    socket =
      socket
      |> assign(:soak_busy, false)
      |> assign(:soak_session, nil)
      |> assign(:warm_machines, fetch_warm_machines())
      |> merge_lab_readiness(meta, result)

    socket =
      case result do
        :ok ->
          probes = Map.get(meta, :stability_probes, %{ok: 0, fail: 0})
          put_flash(
            socket,
            :info,
            "Soak stability window passed — #{probes.ok} probes, 0 failures (bind wait excluded)."
          )

        {:error, reason} ->
          put_flash(socket, :error, "Soak monitor: #{inspect(reason)}")
      end

    {:noreply, socket}
  end

  def handle_info(:refresh_warm_machines, socket) do
    if socket.assigns.live_action == :machines do
      schedule_warm_refresh()
      {:noreply, assign(socket, :warm_machines, fetch_warm_machines())}
    else
      {:noreply, socket}
    end
  end

  # --- Events: select image from catalog ---

  @impl true
  def handle_event("select_image", %{"id" => id_str}, socket) do
    entry =
      try do
        LabCatalog.get(String.to_existing_atom(id_str))
      rescue
        _ -> nil
      end

    if entry do
      {:noreply,
       socket
       |> assign(:selected_image, entry.ref)
       |> assign(:selected_use_image_cmd, entry.use_image_cmd)
       |> assign(:selected_container_cmd, entry.container_cmd)
       |> assign(:selected_catalog_id, entry.id)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("image_input_changed", %{"image_ref" => ref}, socket) do
    ref = String.trim(ref)

    catalog_match = Enum.find(LabCatalog.entries(), &(&1.ref == ref))

    if catalog_match do
      {:noreply,
       socket
       |> assign(:selected_image, catalog_match.ref)
       |> assign(:selected_use_image_cmd, catalog_match.use_image_cmd)
       |> assign(:selected_container_cmd, catalog_match.container_cmd)
       |> assign(:selected_catalog_id, catalog_match.id)}
    else
      {:noreply,
       socket
       |> assign(:selected_image, ref)
       |> assign(:selected_use_image_cmd, true)
       |> assign(:selected_container_cmd, nil)
       |> assign(:selected_catalog_id, nil)}
    end
  end

  # --- Events: build image ---

  @impl true
  def handle_event("build_lab_image", %{"id" => id_str}, socket) do
    entry = LabCatalog.get(String.to_existing_atom(id_str))

    cond do
      is_nil(entry) ->
        {:noreply, put_flash(socket, :error, "Unknown catalog entry.")}

      is_nil(entry.build_context) ->
        {:noreply, put_flash(socket, :error, "#{entry.label} has no local build context.")}

      socket.assigns.image_build_busy ->
        {:noreply, put_flash(socket, :error, "A build is already in progress.")}

      true ->
        LabImageBuilder.build_async(entry)

        {:noreply,
         socket
         |> assign(image_build_log: [], image_build_busy: true)}
    end
  end

  # --- Events: pull image from registry ---

  @impl true
  def handle_event("pull_image", %{"id" => id_str}, socket) do
    entry =
      try do
        LabCatalog.get(String.to_existing_atom(id_str))
      rescue
        _ -> nil
      end

    cond do
      is_nil(entry) ->
        {:noreply, put_flash(socket, :error, "Unknown catalog entry.")}

      socket.assigns.image_pull_busy ->
        {:noreply, put_flash(socket, :error, "A pull is already in progress.")}

      true ->
        pid = self()
        ref = entry.ref

        Task.start(fn ->
          result = Companion.Docker.impl().image_pull(ref)
          send(pid, {:image_pull_done, ref, result})
        end)

        {:noreply, assign(socket, :image_pull_busy, true)}
    end
  end

  # --- Events: run pre-flight ---

  @impl true
  def handle_event("run_vm_manager_preflight", _params, socket) do
    ref = socket.assigns.selected_image

    if ref == "" do
      {:noreply, put_flash(socket, :error, "Enter an image reference first.")}
    else
      overrides = [
        image: ref,
        use_image_default_cmd: socket.assigns.selected_use_image_cmd
      ]

      overrides =
        if socket.assigns.selected_container_cmd do
          Keyword.put(overrides, :container_cmd, socket.assigns.selected_container_cmd)
        else
          overrides
        end

      try do
        case Runner.run_vm_manager_preflight(overrides) do
          :ok ->
            {:noreply,
             socket
             |> assign(vm_preflight_log: [], vm_preflight_result: nil, vm_preflight_busy: true)}

          {:error, :busy} ->
            {:noreply,
             put_flash(socket, :error, "A pre-flight run is already in progress.")}

          {:error, :runner_supervisor_not_started} ->
            {:noreply,
             put_flash(socket, :error, "Runner supervisor not running. Try: docker compose restart companion")}

          {:error, {:runner_start_failed, reason}} ->
            {:noreply,
             put_flash(socket, :error, "Could not start runner (#{inspect(reason)}). Try: docker compose restart companion")}
        end
      catch
        :exit, reason ->
          {:noreply,
           put_flash(socket, :error, "Runner unavailable (#{inspect(reason)}). Try: docker compose restart companion")}
      end
    end
  end

  # --- Events: destroy all lab containers ---

  @impl true
  def handle_event("destroy_all_lab", _params, socket) do
    if socket.assigns.destroying do
      {:noreply, put_flash(socket, :error, "Destroy already in progress.")}
    else
      docker = Companion.Docker.impl()

      case docker.container_list(filters: %{"label" => ["telvm.vm_manager_lab=true"]}) do
        {:ok, containers} when containers == [] ->
          {:noreply, put_flash(socket, :info, "No lab containers running.")}

        {:ok, containers} ->
          count = length(containers)

          Task.start(fn ->
            for c <- containers do
              id = c["Id"]
              _ = docker.container_stop(id, timeout_sec: 5)
              _ = docker.container_remove(id, force: true)
            end
          end)

          {:noreply,
           socket
           |> assign(:lab_readiness, %{})
           |> assign(:soak_session, nil)
           |> assign(:preflight_session, nil)
           |> put_flash(:info, "Destroying #{count} lab container(s)…")}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Could not list containers: #{inspect(reason)}")}
      end
    end
  end

  # --- Events: start and monitor (soak test) ---

  @impl true
  def handle_event("start_and_monitor", _params, socket) do
    ref = socket.assigns.selected_image

    if ref == "" do
      {:noreply, put_flash(socket, :error, "Enter an image reference first.")}
    else
      if socket.assigns.soak_busy do
        {:noreply, put_flash(socket, :error, "A soak monitor is already in progress.")}
      else
        overrides = [
          image: ref,
          use_image_default_cmd: socket.assigns.selected_use_image_cmd
        ]

        overrides =
          if socket.assigns.selected_container_cmd do
            Keyword.put(overrides, :container_cmd, socket.assigns.selected_container_cmd)
          else
            overrides
          end

        SoakRunner.soak_run_async(overrides)

        {:noreply,
         socket
         |> assign(vm_preflight_log: [], soak_busy: true)}
      end
    end
  end

  # --- Events: stop individual machine ---

  @impl true
  def handle_event("stop_machine", %{"id" => cid}, socket) do
    docker = Companion.Docker.impl()

    Task.start(fn ->
      _ = docker.container_stop(cid, timeout_sec: 5)
      _ = docker.container_remove(cid, force: true)
    end)

    readiness = Map.delete(socket.assigns.lab_readiness || %{}, cid)

    soak_s = socket.assigns[:soak_session]
    pf_s = socket.assigns[:preflight_session]

    socket =
      socket
      |> assign(:lab_readiness, readiness)
      |> then(fn s ->
        s =
          if soak_s && soak_s.container_id == cid,
            do: assign(s, :soak_session, nil),
            else: s

        if pf_s && pf_s.container_id == cid,
          do: assign(s, :preflight_session, nil),
          else: s
      end)
      |> put_flash(:info, "Stopping container #{String.slice(cid, 0, 12)}…")
      |> assign(:warm_machines, fetch_warm_machines())

    {:noreply, socket}
  end

  defp merge_lab_readiness(socket, meta, result) when is_map(meta) do
    cid = Map.get(meta, :container_id)

    if is_binary(cid) and cid != "" do
      soak =
        case result do
          :ok -> :ok
          {:error, _} -> :error
        end

      entry = %{
        soak: soak,
        soak_at: DateTime.utc_now() |> DateTime.truncate(:second),
        image: Map.get(meta, :image),
        stability_probes: Map.get(meta, :stability_probes),
        exposed_port: Map.get(meta, :exposed_port)
      }

      assign(socket, :lab_readiness, Map.put(socket.assigns.lab_readiness, cid, entry))
    else
      socket
    end
  end

  # --- Render ---

  @impl true
  def render(assigns) do
    case assigns.live_action do
      :topology ->
        topology(assigns)

      :machines ->
        machines(assigns)

      action when action in [:legacy_certificate_redirect, :legacy_images_redirect, :legacy_preflight_redirect] ->
        ~H"""
        <div class="sr-only" aria-hidden="true">redirecting…</div>
        """

      _ ->
        checks(assigns)
    end
  end

  # --- Machines tab (unified) ---

  defp machines(assigns) do
    ~H"""
    <div class="telvm-terminal max-w-5xl mx-auto px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />

      <div class="flex flex-wrap items-end justify-between gap-2 border-b border-cyan-900/30 pb-2 mb-3">
        <div class="text-[11px] sm:text-xs uppercase tracking-[0.2em] text-cyan-400/90 font-semibold">
          telvm · mission console
        </div>
        <div :if={@vm_preflight_result != nil} class="text-[10px] font-mono uppercase tracking-wide">
          <span class="text-zinc-600">last pre-flight ·</span>
          <span class={if(@vm_preflight_result == :ok, do: "text-emerald-400", else: "text-rose-400")}>
            {if @vm_preflight_result == :ok, do: "PASS", else: "FAIL"}
          </span>
        </div>
      </div>

      <p class="text-zinc-500 text-[11px] mb-4 font-mono leading-relaxed max-w-2xl border-l-2 border-amber-700/50 pl-2">
        Ephemeral pre-flight or persistent soak → warm asset. Engine via Finch → docker.sock. Next: agent binary + preview proxy.
      </p>

      <div
        class="mb-5 rounded-sm border border-cyan-900/40 bg-zinc-950/90 shadow-[inset_0_1px_0_0_rgba(34,211,238,0.06)] p-3"
        id="warm-machines-section"
      >
        <div class="text-cyan-500/80 text-[10px] uppercase tracking-[0.15em] mb-2 font-semibold">warm assets</div>
        <div :if={@warm_machines == []} class="text-zinc-600 text-xs font-mono italic">
          No warm machines — run soak or leave a lab container up.
        </div>
        <div :if={@warm_machines != []} class="overflow-x-auto">
          <div class="min-w-[52rem]">
            <div class="grid grid-cols-12 gap-x-1 px-2 py-1 border-b border-zinc-800/90 text-[9px] sm:text-[10px] uppercase tracking-wide text-zinc-500 bg-black/50 font-mono">
              <span class="col-span-2">name</span>
              <span class="col-span-2">image</span>
              <span class="col-span-1">ports</span>
              <span class="col-span-2">live</span>
              <span class="col-span-1">soak</span>
              <span class="col-span-1">probe</span>
              <span class="col-span-1">st</span>
              <span class="col-span-2">action</span>
            </div>
            <div class="max-h-[12rem] overflow-y-auto overflow-x-visible">
              <div
                :for={m <- @warm_machines}
                class={[
                  "grid grid-cols-12 gap-x-1 px-2 py-1.5 border-b border-zinc-800/40 text-[11px] font-mono items-center",
                  warm_row_class(m, @soak_session, @preflight_session)
                ]}
              >
                <div class="col-span-2 text-zinc-300 truncate" title={m.name}>{m.name}</div>
                <div class="col-span-2 text-zinc-500 truncate text-[10px]" title={m.image}>{m.image}</div>
                <div class="col-span-1 tabular-nums text-[10px]">
                  <span :if={m.ports == [] and m.internal_ports == []} class="text-zinc-600">—</span>
                  <span :for={p <- m.ports} class="block">
                    <a
                      href={"/app/#{m.name}/port/#{p}/"}
                      target="_blank"
                      rel="noopener"
                      class="text-sky-400/90 underline decoration-dotted underline-offset-2 hover:text-cyan-300 transition-colors"
                      title={"Open port #{p} via proxy"}
                    >
                      {p}
                    </a>
                  </span>
                  <span
                    :for={p <- m.internal_ports}
                    class="block text-zinc-700 cursor-default"
                    title={"Internal socket — not an HTTP server (port #{p})"}
                  >
                    {p}
                  </span>
                  <a
                    href={"/explore/#{m.id}"}
                    target="_blank"
                    rel="noopener"
                    title="Read-only files in Monaco (docker exec)"
                    class="inline-block mt-1 text-violet-400/85 text-[10px] underline decoration-dotted underline-offset-2 hover:text-violet-300"
                  >
                    monaco
                  </a>
                </div>
                <div class="col-span-2">
                  <span class={live_activity_class(m, @soak_session, @preflight_session)}>
                    {live_activity_txt(m, @soak_session, @preflight_session)}
                  </span>
                </div>
                <div class="col-span-1">
                  <span class={soak_badge_class(@lab_readiness[m.id])}>{soak_badge_txt(@lab_readiness[m.id])}</span>
                </div>
                <div class="col-span-1">
                  <span class={port_probe_class(@lab_readiness[m.id], m.ports)}>{port_probe_txt(@lab_readiness[m.id], m.ports)}</span>
                </div>
                <div class={["col-span-1 font-medium text-[10px]", warm_status_class(m.status)]}>{String.slice(m.status, 0, 4)}</div>
                <div class="col-span-2 flex items-center justify-end">
                  <button
                    type="button"
                    phx-click="stop_machine"
                    phx-value-id={m.id}
                    class="px-2 py-0.5 text-[10px] rounded-sm border border-rose-900/70 text-rose-300/90 bg-rose-950/30 hover:bg-rose-900/40 uppercase tracking-wide"
                  >
                    stop
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>

      <%!-- Image selection buttons --%>
      <div class="mb-4">
        <div class="text-amber-600/70 text-[10px] uppercase tracking-[0.15em] mb-2 font-semibold">image select</div>
        <div class="flex flex-wrap gap-2">
          <div :for={entry <- @lab_catalog} class="flex items-center gap-1">
            <button
              type="button"
              phx-click="select_image"
              phx-value-id={entry.id}
              class={image_btn_class(@selected_catalog_id == entry.id)}
            >
              {entry.label}
            </button>
            <button
              :if={not entry.available}
              type="button"
              phx-click="pull_image"
              phx-value-id={entry.id}
              disabled={@image_pull_busy}
              title={"Pull #{entry.ref} from registry"}
              class="px-1.5 py-1 text-[9px] font-mono rounded-sm border border-sky-800/60 text-sky-400/80 bg-sky-950/40 hover:bg-sky-900/40 hover:text-sky-300 transition-colors disabled:opacity-40 disabled:cursor-not-allowed uppercase tracking-wide"
            >
              {if @image_pull_busy, do: "…", else: "pull"}
            </button>
          </div>
        </div>
        <p :if={@image_pull_busy} class="text-sky-400/70 text-[10px] font-mono mt-1 animate-pulse">
          Pulling image from registry — this may take a minute…
        </p>
      </div>

      <%!-- BYOI input --%>
      <div class="mb-4 max-w-xl">
        <label for="byoi-image-ref" class="block text-cyan-600/60 text-[10px] uppercase tracking-[0.12em] mb-1 font-semibold">
          image ref / BYOI
        </label>
        <input
          type="text"
          name="image_ref"
          id="byoi-image-ref"
          value={@selected_image}
          phx-change="image_input_changed"
          phx-debounce="300"
          autocomplete="off"
          placeholder="ghcr.io/org/image:tag"
          disabled={@vm_preflight_busy}
          class="w-full px-2 py-1.5 text-xs font-mono border border-zinc-700 rounded-sm bg-zinc-950/80 text-zinc-200 placeholder:text-zinc-600 focus:outline-none focus:ring-1 focus:ring-amber-600/50 disabled:opacity-50"
        />
        <p class="text-zinc-600 text-[10px] mt-1">
          Click a button above or type any Docker image reference. Unknown images use their baked-in CMD.
        </p>
      </div>

      <div class="text-amber-600/70 text-[10px] uppercase tracking-[0.15em] mb-2 font-semibold">actions</div>
      <%!-- Action row --%>
      <div class="flex flex-wrap items-center gap-3 mb-4">
        <button
          type="button"
          phx-click="run_vm_manager_preflight"
          disabled={@vm_preflight_busy}
          class={[
            "px-4 py-2 text-xs font-mono font-semibold rounded-sm border transition-colors uppercase tracking-wide",
            @vm_preflight_busy && "border-zinc-700 text-zinc-600 cursor-not-allowed opacity-70",
            !@vm_preflight_busy && "border-amber-600/80 text-amber-200 bg-amber-950/50 hover:bg-amber-900/50"
          ]}
        >
          Run pre-flight
        </button>
        <button
          type="button"
          phx-click="start_and_monitor"
          disabled={@soak_busy or @vm_preflight_busy}
          class={[
            "px-4 py-2 text-xs font-mono font-semibold rounded-sm border transition-colors uppercase tracking-wide",
            (@soak_busy or @vm_preflight_busy) && "border-zinc-700 text-zinc-600 cursor-not-allowed opacity-70",
            !(@soak_busy or @vm_preflight_busy) && "border-cyan-700/80 text-cyan-200 bg-cyan-950/40 hover:bg-cyan-900/40"
          ]}
        >
          Start &amp; monitor (60s)
        </button>
        <span :if={@vm_preflight_busy} class="text-amber-500/80 text-[10px] font-mono animate-pulse">run…</span>
        <span :if={@soak_busy} class="text-cyan-400/80 text-[10px] font-mono animate-pulse">soak…</span>

        <div class="flex-1 min-w-[1rem]" />

        <button
          type="button"
          phx-click="destroy_all_lab"
          class="px-3 py-1.5 text-[10px] font-mono font-medium rounded-sm border border-rose-900/70 text-rose-300/90 bg-rose-950/30 hover:bg-rose-900/40 uppercase tracking-wide"
        >
          destroy all lab
        </button>
      </div>

      <%!-- Result banner --%>
      <div :if={@vm_preflight_result != nil} class="mb-4 text-xs font-mono font-medium">
        <p
          :if={@vm_preflight_result == :ok}
          class="text-emerald-400 border border-emerald-800/50 bg-emerald-950/20 px-3 py-2 rounded-sm"
        >
          SORTIE OK — lifecycle + HTTP probe for {hd(String.split(@selected_image, " "))}
        </p>
        <p
          :if={@vm_preflight_result != :ok}
          class="text-rose-400 border border-rose-900/50 bg-rose-950/20 px-3 py-2 rounded-sm break-words"
        >
          SORTIE FAIL — {inspect(@vm_preflight_result)}
        </p>
      </div>

      <%!-- Terminal log --%>
      <div class="text-cyan-600/70 text-[10px] uppercase tracking-[0.15em] mb-1 font-semibold">comms</div>
      <div
        id="machines-log"
        phx-hook="ScrollBottom"
        class="h-[20rem] overflow-y-auto overflow-x-auto border border-zinc-800/90 bg-black/60 p-2 font-mono text-[11px] sm:text-xs leading-relaxed space-y-0.5 rounded-sm shadow-inner"
      >
        <div :if={@vm_preflight_log == []} class="text-zinc-600">
          Awaiting orders — pre-flight or soak.
        </div>
        <div :for={entry <- @vm_preflight_log} class={vm_preflight_line_class(elem(entry, 0))}>
          <span class="text-zinc-600 tabular-nums mr-2">{vm_preflight_ts(elem(entry, 1))}</span>
          <span class="text-zinc-500 mr-2">[{vm_preflight_kind_label(elem(entry, 0))}]</span>
          <span>{elem(entry, 2)}</span>
        </div>
      </div>

      <%!-- Build log (for local builds like Go HTTP lab) --%>
      <div :if={@image_build_log != [] or @image_build_busy} class="mt-4">
        <div class="text-zinc-500 text-[10px] uppercase tracking-wide mb-1 font-semibold">build</div>
        <div
          id="image-build-log"
          phx-hook="ScrollBottom"
          class="h-40 overflow-y-auto overflow-x-auto border border-zinc-800/80 bg-black/40 p-2 font-mono text-[11px] sm:text-xs leading-relaxed space-y-0.5 rounded-sm"
        >
          <div :for={{ts, text} <- @image_build_log} class="text-zinc-400">
            <span class="text-zinc-600 tabular-nums mr-2">{Calendar.strftime(ts, "%H:%M:%S UTC")}</span>
            <span>{text}</span>
          </div>
        </div>
      </div>
    </div>

    """
  end

  # --- Checks tab ---

  defp checks(assigns) do
    ~H"""
    <div class="telvm-terminal max-w-5xl mx-auto px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />

      <div class="border-b border-zinc-700/80 pb-2 mb-3 text-[11px] sm:text-xs uppercase tracking-widest text-amber-500/90">
        telvm · OSS
      </div>

      <div id="preflight-rollup" data-rollup={to_string(@report.rollup)} class="mb-4 space-y-1">
        <div class="text-zinc-100 font-semibold">pre-flight</div>
        <p class="text-zinc-500 text-xs leading-relaxed max-w-xl">
          after <span class="text-zinc-400">docker compose up</span>
          · PubSub <span class="text-zinc-400">preflight:updates</span>
          · <span class="text-zinc-400">Companion.PreflightServer</span>
        </p>
        <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 text-xs sm:text-sm mt-2">
          <span class="text-zinc-500">status</span>
          <span class={rollup_class(@report.rollup)}>{rollup_label(@report.rollup)}</span>
          <span class="text-zinc-600">·</span>
          <span class="text-zinc-500 tabular-nums">
            {Calendar.strftime(@report.refreshed_at, "%Y-%m-%d %H:%M:%S UTC")}
          </span>
        </div>
      </div>

      <section class="mb-5" id="preflight-gating-section">
        <div class="text-zinc-500 text-[11px] uppercase tracking-wide mb-1">gating</div>
        <p class="text-zinc-600 text-xs mb-2">
          Rollup = all pass → ready; any fail → blocked; else degraded (warn/skip).
        </p>
        <div class="overflow-x-auto border border-zinc-800/80" id="preflight-gating-table">
          <.term_header cols={["check", "st", "detail"]} />
          <div :for={c <- gating_checks(@report)} id={"preflight-row-#{c.id}"} class="term-row">
            <div class="col-span-5 sm:col-span-5 truncate text-zinc-200" title={c.title}>
              {c.title}
            </div>
            <div class="col-span-2 sm:col-span-2"><.term_status status={c.status} /></div>
            <div class="col-span-12 sm:col-span-5 text-zinc-500 break-words">{c.detail}</div>
          </div>
        </div>
      </section>

      <section class="mb-5" id="preflight-info-section">
        <div class="text-zinc-500 text-[11px] uppercase tracking-wide mb-1">informational</div>
        <div class="overflow-x-auto border border-zinc-800/80" id="preflight-info-table">
          <.term_header cols={["item", "st", "detail"]} />
          <div :for={c <- info_checks(@report)} class="term-row">
            <div class="col-span-5 truncate text-zinc-200" title={c.title}>{c.title}</div>
            <div class="col-span-2"><.term_status status={c.status} /></div>
            <div class="col-span-12 sm:col-span-5 text-zinc-500 break-words">{c.detail}</div>
          </div>
        </div>
      </section>

      <section class="mb-5">
        <div class="text-zinc-500 text-[11px] uppercase tracking-wide mb-1">compose</div>
        <ul class="space-y-2 text-xs">
          <li :for={row <- StackStatus.compose_stack_rows()} class="border-l-2 border-zinc-700 pl-2">
            <span class="text-zinc-300">{row.name}</span>
            <span class="text-zinc-600"> — </span>
            <span class="text-zinc-500">{row.note}</span>
          </li>
        </ul>
      </section>

      <section id="preflight-missing-list">
        <div class="text-zinc-500 text-[11px] uppercase tracking-wide mb-1">not yet</div>
        <ul class="text-xs text-zinc-500 space-y-0.5 font-mono">
          <li>- Docker stats/events + push stream</li>
          <li>- ProxyPlug Finch → /app/… sandboxes</li>
          <li>- Runtime catalog (5 → 21+ images)</li>
          <li>- Sessions, Registry, HealthMonitor vitals UI</li>
        </ul>
      </section>
    </div>
    """
  end

  # --- Topology tab ---

  defp topology(assigns) do
    ~H"""
    <div class="telvm-terminal max-w-5xl mx-auto px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />

      <div class="border-b border-zinc-700/80 pb-2 mb-3 text-[11px] sm:text-xs uppercase tracking-widest text-amber-500/90">
        telvm · topology
      </div>

      <p class="text-zinc-500 text-xs mb-3 max-w-xl">
        Host → Docker Desktop → Compose network. Companion publishes :4000; Engine via mounted socket; example VM is <span class="text-zinc-400">vm_node</span>.
      </p>

      <pre
        id="preflight-topology"
        class="overflow-x-auto whitespace-pre text-xs leading-relaxed text-zinc-400 p-3 border border-zinc-800 bg-black/40"
      >{@host_diagram}</pre>
    </div>
    """
  end

  # --- Helpers ---

  # The Linux ephemeral port range starts at 32768 by default
  # (/proc/sys/net/ipv4/ip_local_port_range). Ports above this threshold are
  # typically kernel-assigned (Node.js IPC, etc.) and not intentional HTTP servers.
  @ephemeral_port_threshold 32_768

  defp fetch_warm_machines do
    alias Companion.VmLifecycle.PortScanner
    docker = Companion.Docker.impl()

    case docker.container_list(filters: %{"label" => ["telvm.vm_manager_lab=true"]}) do
      {:ok, containers} ->
        Enum.map(containers, fn c ->
          info = extract_warm_info(c)

          {proxy_ports, internal_ports} =
            if info.status == "running" do
              case PortScanner.scan_ports(info.id) do
                {:ok, ports} ->
                  Enum.split_with(ports, fn p -> p < @ephemeral_port_threshold end)

                {:error, _} ->
                  {[], []}
              end
            else
              {[], []}
            end

          Map.merge(info, %{ports: proxy_ports, internal_ports: internal_ports})
        end)

      {:error, _} ->
        []
    end
  end

  defp extract_warm_info(c) do
    name =
      case c["Names"] do
        [n | _] -> String.trim_leading(n, "/")
        _ -> String.slice(c["Id"] || "", 0, 12)
      end

    %{
      id: c["Id"],
      name: name,
      image: c["Image"],
      status: c["State"] || c["Status"] || "unknown",
      created: c["Created"]
    }
  end

  defp schedule_warm_refresh do
    Process.send_after(self(), :refresh_warm_machines, 5_000)
  end

  defp vm_preflight_ts(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S UTC")

  defp vm_preflight_kind_label(:narrator), do: "say"
  defp vm_preflight_kind_label(:engine), do: "eng"
  defp vm_preflight_kind_label(_), do: "?"

  defp vm_preflight_line_class(:narrator), do: "text-sky-300/90"
  defp vm_preflight_line_class(:engine), do: "text-zinc-400"
  defp vm_preflight_line_class(_), do: "text-zinc-500"

  defp warm_row_class(m, soak_s, pf_s) do
    active =
      (soak_s && soak_s.container_id == m.id) || (pf_s && pf_s.container_id == m.id)

    if active,
      do: "bg-cyan-950/25 ring-1 ring-inset ring-cyan-700/35",
      else: ""
  end

  defp live_activity_txt(m, soak_s, pf_s) do
    cond do
      soak_s && soak_s.container_id == m.id ->
        case soak_s.phase do
          :bind -> "BIND"
          :stability -> "SOAK"
          _ -> "…"
        end

      pf_s && pf_s.container_id == m.id ->
        case pf_s.phase do
          :preflight -> "INIT"
          :probe -> "PROBE"
          _ -> "…"
        end

      true ->
        "—"
    end
  end

  defp live_activity_class(m, soak_s, pf_s) do
    active =
      (soak_s && soak_s.container_id == m.id) || (pf_s && pf_s.container_id == m.id)

    if active,
      do: "text-cyan-300 font-bold text-[10px] tracking-wide animate-pulse",
      else: "text-zinc-600 text-[10px]"
  end

  defp soak_badge_txt(nil), do: "—"
  defp soak_badge_txt(%{soak: :ok}), do: "OK"
  defp soak_badge_txt(%{soak: :error}), do: "FAIL"
  defp soak_badge_txt(_), do: "—"

  defp soak_badge_class(nil), do: "text-zinc-600 text-[10px]"
  defp soak_badge_class(%{soak: :ok}), do: "text-emerald-400 font-bold text-[10px]"
  defp soak_badge_class(%{soak: :error}), do: "text-rose-400 font-bold text-[10px]"
  defp soak_badge_class(_), do: "text-zinc-600 text-[10px]"

  defp port_probe_txt(nil, _ports), do: "—"

  defp port_probe_txt(%{exposed_port: ep}, ports) when is_list(ports) and is_integer(ep) do
    if ep in ports, do: "OK", else: "!"
  end

  defp port_probe_txt(_, _), do: "—"

  defp port_probe_class(nil, _ports), do: "text-zinc-600 text-[10px]"

  defp port_probe_class(%{exposed_port: ep}, ports) when is_list(ports) and is_integer(ep) do
    if ep in ports, do: "text-emerald-400 font-bold text-[10px]", else: "text-amber-400 font-bold text-[10px]"
  end

  defp port_probe_class(_, _), do: "text-zinc-600 text-[10px]"

  defp warm_status_class("running"), do: "text-emerald-400"
  defp warm_status_class("paused"), do: "text-amber-400"
  defp warm_status_class("exited"), do: "text-zinc-500"
  defp warm_status_class(_), do: "text-zinc-500"

  defp image_btn_class(true) do
    "px-3 py-1.5 text-xs font-semibold rounded-sm border border-amber-600/70 text-amber-300 bg-amber-950/40"
  end

  defp image_btn_class(false) do
    "px-3 py-1.5 text-xs font-medium rounded-sm border border-zinc-700 text-zinc-400 bg-zinc-950/40 hover:border-zinc-600 hover:text-zinc-300 transition-colors"
  end

  # --- Nav ---

  attr :active, :atom, required: true

  defp terminal_nav(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2 text-xs mb-4" aria-label="Pre-flight views">
      <.link patch={~p"/"} class={nav_tab_class(@active, :checks)}>checks</.link>
      <.link patch={~p"/topology"} class={nav_tab_class(@active, :topology)}>topology</.link>
      <.link patch={~p"/machines"} class={nav_tab_class(@active, :machines)}>machines</.link>
    </nav>
    """
  end

  defp nav_tab_class(active, tab) do
    on = active == tab

    [
      "px-2 py-0.5 border rounded-sm transition-colors",
      on && "border-amber-600/60 text-amber-400 bg-zinc-900/50",
      !on && "border-zinc-700 text-zinc-500 hover:text-zinc-300 hover:border-zinc-600"
    ]
  end

  # --- Shared components ---

  attr :cols, :list, required: true

  defp term_header(assigns) do
    ~H"""
    <div class="grid grid-cols-12 gap-x-2 px-2 py-1 border-b border-zinc-800 text-[10px] sm:text-[11px] uppercase tracking-wide text-zinc-600 bg-zinc-900/40">
      <span class="col-span-5">{Enum.at(@cols, 0)}</span>
      <span class="col-span-2">{Enum.at(@cols, 1)}</span>
      <span class="col-span-12 sm:col-span-5">{Enum.at(@cols, 2)}</span>
    </div>
    """
  end

  attr :status, :atom, required: true

  defp term_status(assigns) do
    ~H"""
    <span class={[
      "whitespace-nowrap tabular-nums text-[11px] sm:text-xs font-medium",
      status_class(@status)
    ]}>
      {status_txt(@status)}
    </span>
    """
  end

  defp gating_checks(%{checks: checks}), do: Enum.filter(checks, &(&1.kind == :gating))
  defp info_checks(%{checks: checks}), do: Enum.filter(checks, &(&1.kind == :info))

  defp rollup_label(:ready), do: "READY"
  defp rollup_label(:degraded), do: "DEGRADED"
  defp rollup_label(:blocked), do: "BLOCKED"
  defp rollup_label(_), do: "UNKNOWN"

  defp rollup_class(:ready), do: "text-emerald-400 font-semibold"
  defp rollup_class(:degraded), do: "text-amber-400 font-semibold"
  defp rollup_class(:blocked), do: "text-rose-400 font-semibold"
  defp rollup_class(_), do: "text-zinc-400"

  defp status_txt(:pass), do: "[ OK ]"
  defp status_txt(:fail), do: "[FAIL]"
  defp status_txt(:warn), do: "[WARN]"
  defp status_txt(:skip), do: "[SKIP]"
  defp status_txt(:info), do: "[INFO]"
  defp status_txt(_), do: "[ ?? ]"

  defp status_class(:pass), do: "text-emerald-400"
  defp status_class(:fail), do: "text-rose-400"
  defp status_class(:warn), do: "text-amber-400"
  defp status_class(:skip), do: "text-zinc-500"
  defp status_class(:info), do: "text-sky-400"
  defp status_class(_), do: "text-zinc-400"
end
