defmodule CompanionWeb.StatusLive do
  use CompanionWeb, :live_view

  alias Companion.Preflight
  alias Companion.StackStatus
  alias Companion.VmLifecycle
  alias Companion.VmLifecycle.Runner
  alias Companion.VmLifecycle.SoakRunner
  alias Companion.LabCatalog
  alias Companion.LabImageBuilder

  @default_entry LabCatalog.get(:lab_bun)

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
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
      |> assign(:pending_soak_after_preflight, false)
      |> assign(:explorer_preview_id, nil)
      |> assign(:preview_iframe_src, nil)
      |> assign(:preview_mode, nil)
      |> assign(:lab_verify_tab, "status")
      |> assign(:verify_last_error, nil)
      |> assign(:verify_chain_active, false)
      |> assign(:lab_verify_pass, false)

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
      redirect
      when redirect in [
             :legacy_certificate_redirect,
             :legacy_images_redirect,
             :legacy_preflight_redirect
           ] ->
        {:noreply, push_navigate(socket, to: ~p"/machines", replace: true)}

      action when action in [:machines, :warm_assets] ->
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
      :machines -> "Machines"
      :warm_assets -> "Warm assets"
      _ -> "Pre-flight"
    end
  end

  defp mission_tab?(:machines), do: true
  defp mission_tab?(:warm_assets), do: true
  defp mission_tab?(_), do: false

  # --- PubSub handlers ---

  @impl true
  def handle_info({:report, report}, socket) do
    {:noreply, assign(socket, :report, report)}
  end

  def handle_info({:vm_manager_preflight, {:line, kind, ts, text}}, socket) do
    if mission_tab?(socket.assigns.live_action) || socket.assigns[:vm_preflight_busy] do
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

  def handle_info(
        {:vm_manager_preflight, {:session, %{container_id: _, phase: _} = data}},
        socket
      ) do
    {:noreply, assign(socket, :preflight_session, data)}
  end

  def handle_info({:vm_manager_preflight, {:done, result}}, socket) do
    socket =
      socket
      |> assign(vm_preflight_busy: false, vm_preflight_result: result)
      |> assign(:preflight_session, nil)

    socket =
      if result != :ok do
        socket
        |> assign(:verify_last_error, "Pre-flight: #{inspect(result)}")
        |> assign(:verify_chain_active, false)
        |> assign(:lab_verify_pass, false)
        |> assign(:lab_verify_tab, "errors")
      else
        socket
      end

    if result == :ok && socket.assigns[:pending_soak_after_preflight] do
      overrides =
        socket.assigns
        |> lab_overrides_from_assigns()
        |> Keyword.put(:soak_duration_ms, 15_000)

      SoakRunner.soak_run_async(overrides)

      {:noreply,
       socket
       |> assign(:pending_soak_after_preflight, false)
       |> assign(:vm_preflight_log, [])
       |> assign(:soak_busy, true)}
    else
      {:noreply, assign(socket, :pending_soak_after_preflight, false)}
    end
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
    if mission_tab?(socket.assigns.live_action) || socket.assigns[:soak_busy] do
      log = socket.assigns[:vm_preflight_log] || []
      log = log ++ [{kind, ts, text}]
      log = Enum.take(log, -400)
      {:noreply, assign(socket, :vm_preflight_log, log)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:soak_monitor, {:done, result, meta}}, socket) when is_map(meta) do
    chain? = socket.assigns[:verify_chain_active] == true

    socket =
      socket
      |> assign(:soak_busy, false)
      |> assign(:soak_session, nil)
      |> assign(:warm_machines, fetch_warm_machines())
      |> merge_lab_readiness(meta, result)

    socket =
      cond do
        chain? && result == :ok ->
          probes = Map.get(meta, :stability_probes, %{ok: 0, fail: 0})

          socket
          |> assign(:lab_verify_pass, true)
          |> assign(:verify_last_error, nil)
          |> assign(:verify_chain_active, false)
          |> put_flash(
            :info,
            "Lab verify complete — #{probes.ok} stability probes, 0 failures."
          )

        chain? && match?({:error, _}, result) ->
          {:error, reason} = result

          socket
          |> assign(:verify_last_error, "Soak: #{inspect(reason)}")
          |> assign(:lab_verify_pass, false)
          |> assign(:verify_chain_active, false)
          |> assign(:lab_verify_tab, "errors")
          |> put_flash(:error, "Soak monitor: #{inspect(reason)}")

        true ->
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
      end

    {:noreply, socket}
  end

  def handle_info(:refresh_warm_machines, socket) do
    if mission_tab?(socket.assigns.live_action) do
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

  @impl true
  def handle_event("set_explorer_preview", %{"id" => id}, socket) do
    cur = socket.assigns[:explorer_preview_id]

    {next_id, src, mode} =
      if cur == id do
        {nil, nil, nil}
      else
        {id, "/explore/#{id}?embed=1", :explorer}
      end

    {:noreply,
     socket
     |> assign(:explorer_preview_id, next_id)
     |> assign(:preview_iframe_src, src)
     |> assign(:preview_mode, mode)}
  end

  # --- Events: verify (pre-flight then 15s soak) / extended soak ---

  @impl true
  def handle_event("verify_lab", _params, socket) do
    socket =
      socket
      |> assign(:verify_chain_active, true)
      |> assign(:lab_verify_pass, false)
      |> assign(:verify_last_error, nil)
      |> assign(:lab_verify_tab, "status")

    start_vm_manager_preflight(socket, chain_soak: true)
  end

  @impl true
  def handle_event("start_extended_soak", _params, socket) do
    ref = socket.assigns.selected_image

    if ref == "" do
      {:noreply, put_flash(socket, :error, "Enter an image reference first.")}
    else
      if socket.assigns.soak_busy do
        {:noreply, put_flash(socket, :error, "A soak monitor is already in progress.")}
      else
        overrides =
          socket
          |> lab_overrides_from_assigns()
          |> Keyword.put(:soak_duration_ms, 60_000)

        SoakRunner.soak_run_async(overrides)

        {:noreply,
         socket
         |> assign(:pending_soak_after_preflight, false)
         |> assign(:verify_chain_active, false)
         |> assign(:lab_verify_pass, false)
         |> assign(vm_preflight_log: [], soak_busy: true)}
      end
    end
  end

  @impl true
  def handle_event("set_lab_verify_tab", %{"tab" => tab}, socket)
      when tab in ["status", "errors"] do
    {:noreply, assign(socket, :lab_verify_tab, tab)}
  end

  @impl true
  def handle_event("preview_port", %{"path" => path}, socket) when is_binary(path) do
    {:noreply,
     socket
     |> assign(:preview_iframe_src, path)
     |> assign(:preview_mode, :http)
     |> assign(:explorer_preview_id, nil)}
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

  defp start_vm_manager_preflight(socket, opts) do
    chain_soak = Keyword.get(opts, :chain_soak, false)
    ref = socket.assigns.selected_image

    if ref == "" do
      {:noreply, put_flash(socket, :error, "Enter an image reference first.")}
    else
      overrides = lab_overrides_from_assigns(socket.assigns)

      try do
        case Runner.run_vm_manager_preflight(overrides) do
          :ok ->
            {:noreply,
             socket
             |> assign(:pending_soak_after_preflight, chain_soak)
             |> assign(vm_preflight_log: [], vm_preflight_result: nil, vm_preflight_busy: true)}

          {:error, :busy} ->
            {:noreply, put_flash(socket, :error, "A pre-flight run is already in progress.")}

          {:error, :runner_supervisor_not_started} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Runner supervisor not running. Try: docker compose restart companion"
             )}

          {:error, {:runner_start_failed, reason}} ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Could not start runner (#{inspect(reason)}). Try: docker compose restart companion"
             )}
        end
      catch
        :exit, reason ->
          {:noreply,
           put_flash(
             socket,
             :error,
             "Runner unavailable (#{inspect(reason)}). Try: docker compose restart companion"
           )}
      end
    end
  end

  defp lab_overrides_from_assigns(%{selected_image: ref} = assigns) do
    overrides = [
      image: ref,
      use_image_default_cmd: assigns.selected_use_image_cmd
    ]

    if assigns[:selected_container_cmd] do
      Keyword.put(overrides, :container_cmd, assigns.selected_container_cmd)
    else
      overrides
    end
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
      :machines ->
        machines(assigns)

      :warm_assets ->
        warm_assets(assigns)

      action
      when action in [
             :legacy_certificate_redirect,
             :legacy_images_redirect,
             :legacy_preflight_redirect
           ] ->
        ~H"""
        <div class="sr-only" aria-hidden="true">redirecting…</div>
        """

      _ ->
        preflight(assigns)
    end
  end

  # --- Warm assets tab ---

  defp warm_assets(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />

      <div class="flex flex-wrap items-start justify-between gap-x-4 gap-y-1 telvm-accent-border-b border-b pb-2 mb-2">
        <div class="text-[11px] sm:text-xs uppercase tracking-[0.2em] telvm-accent-text font-semibold shrink-0">
          telvm · warm assets
        </div>
        <p
          class="text-[9px] sm:text-[10px] font-mono leading-snug max-w-md lg:max-w-xl lg:text-right"
          style="color: var(--telvm-shell-muted);"
        >
          Port preview or Monaco (files). Verify or soak on Machines.
        </p>
      </div>

      <div class="lg:grid lg:grid-cols-12 lg:items-start lg:gap-5 flex flex-col gap-4">
        <div class="lg:col-span-5 min-w-0 order-1">
          <.warm_machines_section
            {assigns}
            scroll_class="max-h-[min(52vh,22rem)] lg:max-h-[min(82vh,44rem)] overflow-y-auto pr-1"
          />
        </div>
        <div class="lg:col-span-7 min-w-0 order-2 flex flex-col">
          <.warm_preview_panel {assigns} />
        </div>
      </div>
    </div>
    """
  end

  attr :scroll_class, :string, required: true

  defp warm_machines_section(assigns) do
    ~H"""
    <div
      class="rounded-sm telvm-panel-border border telvm-panel-bg shadow-[inset_0_1px_0_0_var(--telvm-accent-glow)] p-3"
      id="warm-machines-section"
    >
      <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.15em] mb-3 font-semibold">
        warm assets
      </div>
      <div
        :if={@warm_machines == []}
        class="text-[11px] font-mono italic"
        style="color: var(--telvm-shell-muted);"
      >
        No warm machines — run verify or extended soak on Machines, or leave a lab container up.
      </div>
      <div :if={@warm_machines != []} class={["space-y-3", @scroll_class]}>
        <div
          :for={m <- @warm_machines}
          class={[
            "rounded border border-zinc-800/80 bg-black/35 p-3 transition-colors",
            warm_row_class(m, @soak_session, @preflight_session)
          ]}
          style="border-color: color-mix(in oklch, var(--telvm-shell-border) 90%, transparent);"
        >
          <div class="flex flex-wrap items-start justify-between gap-2 mb-2">
            <div class="min-w-0 flex-1">
              <div
                class="text-sm font-medium truncate"
                style="color: var(--telvm-shell-fg);"
                title={m.name}
              >
                {m.name}
              </div>
              <div
                class="text-[10px] truncate font-mono mt-0.5"
                style="color: var(--telvm-shell-muted);"
                title={m.image}
              >
                {m.image}
              </div>
            </div>
            <div class="flex items-center gap-2 shrink-0">
              <span class={live_activity_class(m, @soak_session, @preflight_session)}>
                {live_activity_txt(m, @soak_session, @preflight_session)}
              </span>
              <span class={soak_badge_class(@lab_readiness[m.id])}>
                {soak_badge_txt(@lab_readiness[m.id])}
              </span>
              <span class={port_probe_class(@lab_readiness[m.id], m.ports)}>
                {port_probe_txt(@lab_readiness[m.id], m.ports)}
              </span>
              <span class={["font-medium text-[10px]", warm_status_class(m.status)]}>
                {String.slice(m.status, 0, 4)}
              </span>
              <button
                type="button"
                phx-click="stop_machine"
                phx-value-id={m.id}
                class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-danger"
              >
                stop
              </button>
            </div>
          </div>
          <div
            class="border-t pt-2 mt-1"
            style="border-color: color-mix(in oklch, var(--telvm-shell-border) 85%, transparent);"
          >
            <div class="telvm-accent-text text-[10px] uppercase tracking-[0.12em] font-semibold mb-2">
              endpoints
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <span
                :if={m.ports == [] and m.internal_ports == []}
                class="text-xs"
                style="color: var(--telvm-shell-muted);"
              >
                —
              </span>
              <button
                :for={p <- m.ports}
                type="button"
                phx-click="preview_port"
                phx-value-path={"/app/#{m.name}/port/#{p}/"}
                class={[
                  "inline-flex items-center gap-1 px-2 py-1 rounded-md border text-xs font-mono transition-colors",
                  port_preview_active?(@preview_mode, @preview_iframe_src, m, p) &&
                    "telvm-port-btn-on",
                  !port_preview_active?(@preview_mode, @preview_iframe_src, m, p) &&
                    "telvm-port-btn-off"
                ]}
              >
                :{p}
              </button>
              <span
                :for={p <- m.internal_ports}
                class="inline-flex items-center px-2 py-1 rounded-md border text-[10px] font-mono cursor-default"
                style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-shell-elevated) 80%, transparent); color: var(--telvm-shell-muted);"
                title={"Internal (#{p})"}
              >
                int:{p}
              </span>
              <button
                type="button"
                phx-click="set_explorer_preview"
                phx-value-id={m.id}
                class={[
                  "inline-flex items-center gap-1 px-2 py-1 rounded-md border text-xs font-mono transition-colors",
                  @explorer_preview_id == m.id && "telvm-files-btn-on",
                  @explorer_preview_id != m.id && "telvm-files-btn-off"
                ]}
              >
                <.icon name="hero-folder-open" class="size-3.5" /> files
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp warm_preview_panel(assigns) do
    ~H"""
    <div class="flex flex-col flex-1 min-h-0 h-full" id="lab-preview-frame">
      <div
        class="text-[10px] uppercase tracking-wide mb-1 font-semibold"
        style="color: var(--telvm-shell-muted);"
      >
        preview
      </div>
      <iframe
        :if={@preview_iframe_src != nil}
        src={@preview_iframe_src}
        class="telvm-warm-preview-frame w-full shrink-0 rounded border bg-black/50"
        style="border-color: var(--telvm-shell-border);"
        title="Lab preview"
      />
      <div
        :if={@preview_iframe_src == nil}
        class="telvm-warm-preview-frame w-full shrink-0 rounded border flex flex-col items-center justify-center text-center px-4 py-6 bg-black/25 overflow-hidden"
        style="border-color: color-mix(in oklch, var(--telvm-shell-border) 75%, transparent); border-style: dashed;"
      >
        <p class="telvm-accent-text text-xs font-semibold mb-2">No preview yet</p>
        <p class="text-[11px] max-w-sm leading-relaxed mb-3" style="color: var(--telvm-shell-muted);">
          Choose a published port (for example
          <span class="telvm-accent-dim-text font-mono">:3333</span>
          on the default Node image) or open
          <span class="telvm-accent-dim-text font-mono">files</span>
          for the Monaco editor.
        </p>
        <p class="text-[10px] font-mono opacity-70" style="color: var(--telvm-shell-muted);">
          The frame stays here so layout matches when a preview is active.
        </p>
      </div>
    </div>
    """
  end

  # --- Machines tab (catalog + lab verify + build log) ---

  defp machines(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />

      <div class="flex flex-wrap items-end justify-between gap-2 telvm-accent-border-b border-b pb-2 mb-4">
        <div class="text-[11px] sm:text-xs uppercase tracking-[0.2em] telvm-accent-text font-semibold">
          telvm · mission console
        </div>
      </div>

      <p
        class="telvm-prose-bar text-[11px] mb-5 font-mono leading-relaxed max-w-2xl border-l-2 pl-2"
        style="color: var(--telvm-shell-muted);"
      >
        Ephemeral pre-flight or persistent soak → warm asset. Engine via Finch → docker.sock.
      </p>

      <%!-- Image & runtime (top) --%>
      <section
        class="mb-5 rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4"
        id="lab-image-section"
      >
        <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.18em] mb-3 font-semibold">
          image &amp; runtime
        </div>
        <div
          class="grid gap-2 mb-4 justify-start [grid-template-columns:repeat(auto-fill,100px)]"
          id="lab-catalog-grid"
        >
          <div :for={entry <- @lab_catalog} class="flex w-[100px] flex-col gap-1 shrink-0">
            <button
              type="button"
              phx-click="select_image"
              phx-value-id={entry.id}
              class={[
                "w-full min-h-[2.75rem] min-w-0 px-1.5 py-1.5 text-left rounded-md border text-[10px] font-medium transition-colors",
                @selected_catalog_id == entry.id && "telvm-catalog-chip-on",
                @selected_catalog_id != entry.id &&
                  "border-zinc-700/80 bg-black/25 hover:border-zinc-600"
              ]}
              style={
                if(@selected_catalog_id != entry.id, do: "color: var(--telvm-shell-muted)", else: nil)
              }
            >
              <span class="inline-flex items-center gap-1 min-w-0">
                <.icon
                  name={entry.icon}
                  class="size-3.5 sm:size-4 shrink-0 opacity-90"
                />
                <span class="truncate leading-tight">{entry.label}</span>
              </span>
            </button>
            <button
              :if={not entry.available}
              type="button"
              phx-click="pull_image"
              phx-value-id={entry.id}
              disabled={@image_pull_busy}
              title={"Pull #{entry.ref}"}
              class="w-full text-[9px] py-0.5 rounded border telvm-pull-btn disabled:opacity-40"
            >
              {if @image_pull_busy, do: "…", else: "pull"}
            </button>
          </div>
        </div>
        <p
          :if={@image_pull_busy}
          class="telvm-accent-text text-[10px] font-mono mb-3 animate-pulse opacity-90"
        >
          Pulling image…
        </p>
        <div class="max-w-2xl">
          <label
            for="byoi-image-ref"
            class="block telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] mb-1 font-semibold"
          >
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
            class="w-full px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring disabled:opacity-50 placeholder:opacity-60"
            style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
          />
          <p class="text-[10px] mt-1.5" style="color: var(--telvm-shell-muted);">
            Pick a chip or paste any Docker reference. Custom CMD may be required for verify to pass.
          </p>
        </div>
      </section>

      <%!-- Lab verification card --%>
      <section
        class="mb-5 rounded-sm telvm-panel-border border telvm-panel-bg telvm-verify-card p-3 sm:p-4"
        id="lab-verify-card"
      >
        <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
          <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.15em] font-semibold">
            lab verification
          </div>
          <div
            class="flex rounded overflow-hidden text-[10px]"
            style="border: 1px solid var(--telvm-shell-border);"
          >
            <button
              type="button"
              phx-click="set_lab_verify_tab"
              phx-value-tab="status"
              class={[
                "px-2 py-1",
                @lab_verify_tab == "status" && "telvm-nav-tab-active",
                @lab_verify_tab != "status" && "telvm-nav-tab-idle"
              ]}
            >
              status
            </button>
            <button
              type="button"
              phx-click="set_lab_verify_tab"
              phx-value-tab="errors"
              class={[
                "px-2 py-1 border-l",
                @lab_verify_tab == "errors" && "telvm-nav-tab-active",
                @lab_verify_tab != "errors" && "telvm-nav-tab-idle"
              ]}
              style="border-left-color: var(--telvm-shell-border);"
            >
              errors
            </button>
          </div>
        </div>

        <div :if={@lab_verify_tab == "status"} class="space-y-4">
          <div class="flex flex-wrap items-center gap-4 min-h-[3rem]">
            <div class="flex items-center gap-3">
              <div
                :if={@vm_preflight_busy or @soak_busy}
                class="relative flex h-12 w-12 items-center justify-center"
              >
                <span class="absolute inline-flex h-full w-full animate-ping rounded-full telvm-ping-outer opacity-60">
                </span>
                <span class="relative inline-flex h-9 w-9 rounded-full border-2 telvm-ping-inner">
                </span>
              </div>
              <div
                :if={@lab_verify_pass and not @vm_preflight_busy and not @soak_busy}
                class="flex h-12 w-12 items-center justify-center rounded-full border-2 telvm-pass-ring"
              >
                <.icon name="hero-check-circle" class="size-7 telvm-text-ok" />
              </div>
              <div
                :if={
                  not @lab_verify_pass and not @vm_preflight_busy and not @soak_busy and
                    @verify_last_error == nil
                }
                class="flex h-12 w-12 items-center justify-center rounded-full border border-dashed"
                style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-shell-elevated) 70%, transparent);"
              >
                <span
                  class="text-[9px] text-center leading-tight"
                  style="color: var(--telvm-shell-muted);"
                >
                  idle
                </span>
              </div>
              <div class="text-[11px] max-w-md" style="color: var(--telvm-shell-muted);">
                <span :if={@vm_preflight_busy} class="telvm-accent-text">Pre-flight running…</span>
                <span :if={@soak_busy and not @vm_preflight_busy} class="telvm-accent-dim-text">
                  Soak probing…
                </span>
                <span
                  :if={@lab_verify_pass and not @vm_preflight_busy and not @soak_busy}
                  class="telvm-text-ok font-medium"
                >
                  Ready — lifecycle + HTTP + soak passed for {hd(String.split(@selected_image, " "))}
                </span>
                <span
                  :if={
                    @verify_last_error != nil && not @lab_verify_pass && not @vm_preflight_busy &&
                      not @soak_busy
                  }
                  class="telvm-text-danger-ink text-[11px]"
                >
                  Last run failed — see Errors tab.
                </span>
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-2 sm:ml-auto">
              <button
                type="button"
                phx-click="verify_lab"
                disabled={@soak_busy or @vm_preflight_busy}
                class={[
                  "px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide",
                  (@soak_busy or @vm_preflight_busy) &&
                    "cursor-not-allowed opacity-60 border-zinc-700",
                  !(@soak_busy or @vm_preflight_busy) && "telvm-btn-primary"
                ]}
                style={
                  if(@soak_busy or @vm_preflight_busy,
                    do: "color: var(--telvm-shell-muted)",
                    else: nil
                  )
                }
              >
                Verify (pre-flight + 15s soak)
              </button>
              <button
                type="button"
                phx-click="start_extended_soak"
                disabled={@soak_busy or @vm_preflight_busy}
                class={[
                  "px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide",
                  (@soak_busy or @vm_preflight_busy) &&
                    "cursor-not-allowed opacity-60 border-zinc-700",
                  !(@soak_busy or @vm_preflight_busy) && "telvm-btn-secondary"
                ]}
                style={
                  if(@soak_busy or @vm_preflight_busy,
                    do: "color: var(--telvm-shell-muted)",
                    else: nil
                  )
                }
              >
                Extended soak (60s)
              </button>
              <button
                type="button"
                phx-click="destroy_all_lab"
                class="px-2.5 py-1.5 text-[10px] font-mono rounded-md border uppercase tracking-wide telvm-btn-danger"
              >
                destroy all lab
              </button>
            </div>
          </div>
        </div>

        <div :if={@lab_verify_tab == "errors"} class="min-h-[6rem]">
          <p
            :if={@verify_last_error == nil}
            class="text-xs font-mono"
            style="color: var(--telvm-shell-muted);"
          >
            No errors recorded for the last run.
          </p>
          <pre
            :if={@verify_last_error != nil}
            class="text-xs font-mono whitespace-pre-wrap break-all rounded-md p-3 overflow-x-auto telvm-error-box"
          >{@verify_last_error}</pre>
        </div>
      </section>

      <%!-- Build log (Go HTTP lab local build) --%>
      <div :if={@image_build_log != [] or @image_build_busy} class="mt-4">
        <div
          class="text-[10px] uppercase tracking-wide mb-1 font-semibold"
          style="color: var(--telvm-shell-muted);"
        >
          build
        </div>
        <div
          id="image-build-log"
          phx-hook="ScrollBottom"
          class="h-40 overflow-y-auto overflow-x-auto p-2 font-mono text-[11px] sm:text-xs leading-relaxed space-y-0.5 rounded-sm"
          style="border: 1px solid var(--telvm-shell-border); background: var(--telvm-input-bg);"
        >
          <div :for={{ts, text} <- @image_build_log} style="color: var(--telvm-shell-muted);">
            <span class="tabular-nums mr-2 opacity-70">
              {Calendar.strftime(ts, "%H:%M:%S UTC")}
            </span>
            <span>{text}</span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Pre-flight tab (stack health) ---

  defp preflight(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />

      <div class="telvm-accent-border-b border-b pb-2 mb-3 text-[11px] sm:text-xs uppercase tracking-widest telvm-accent-text">
        telvm · OSS
      </div>

      <div class="lg:grid lg:grid-cols-2 lg:gap-6 lg:items-start">
        <div class="min-w-0 space-y-5">
          <div id="preflight-rollup" data-rollup={to_string(@report.rollup)} class="mb-4 space-y-1">
            <div class="font-semibold" style="color: var(--telvm-shell-fg);">pre-flight</div>
            <p class="text-xs leading-relaxed max-w-xl" style="color: var(--telvm-shell-muted);">
              after <span class="telvm-accent-dim-text">docker compose up</span>
              · PubSub <span class="telvm-accent-dim-text">preflight:updates</span>
              · <span class="telvm-accent-dim-text">Companion.PreflightServer</span>
            </p>
            <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 text-xs sm:text-sm mt-2">
              <span style="color: var(--telvm-shell-muted);">status</span>
              <span class={rollup_class(@report.rollup)}>{rollup_label(@report.rollup)}</span>
              <span style="color: var(--telvm-shell-muted);">·</span>
              <span class="tabular-nums" style="color: var(--telvm-shell-muted);">
                {Calendar.strftime(@report.refreshed_at, "%Y-%m-%d %H:%M:%S UTC")}
              </span>
            </div>
          </div>

          <section class="mb-5" id="preflight-gating-section">
            <div
              class="text-[11px] uppercase tracking-wide mb-1"
              style="color: var(--telvm-shell-muted);"
            >
              gating
            </div>
            <p class="text-xs mb-2" style="color: var(--telvm-shell-muted);">
              Rollup = all pass → ready; any fail → blocked; else degraded (warn/skip).
            </p>
            <div class="overflow-x-auto telvm-panel-border border" id="preflight-gating-table">
              <.term_header cols={["check", "st", "detail"]} />
              <div :for={c <- gating_checks(@report)} id={"preflight-row-#{c.id}"} class="term-row">
                <div
                  class="col-span-5 sm:col-span-5 truncate"
                  style="color: var(--telvm-shell-fg);"
                  title={c.title}
                >
                  {c.title}
                </div>
                <div class="col-span-2 sm:col-span-2"><.term_status status={c.status} /></div>
                <div
                  class="col-span-12 sm:col-span-5 break-words"
                  style="color: var(--telvm-shell-muted);"
                >
                  {c.detail}
                </div>
              </div>
            </div>
          </section>

          <section class="mb-5" id="preflight-info-section">
            <div
              class="text-[11px] uppercase tracking-wide mb-1"
              style="color: var(--telvm-shell-muted);"
            >
              informational
            </div>
            <div class="overflow-x-auto telvm-panel-border border" id="preflight-info-table">
              <.term_header cols={["item", "st", "detail"]} />
              <div :for={c <- info_checks(@report)} class="term-row">
                <div class="col-span-5 truncate" style="color: var(--telvm-shell-fg);" title={c.title}>
                  {c.title}
                </div>
                <div class="col-span-2"><.term_status status={c.status} /></div>
                <div
                  class="col-span-12 sm:col-span-5 break-words"
                  style="color: var(--telvm-shell-muted);"
                >
                  {c.detail}
                </div>
              </div>
            </div>
          </section>

          <section class="mb-5">
            <div
              class="text-[11px] uppercase tracking-wide mb-1"
              style="color: var(--telvm-shell-muted);"
            >
              compose
            </div>
            <ul class="space-y-2 text-xs">
              <li
                :for={row <- StackStatus.compose_stack_rows()}
                class="border-l-2 pl-2 telvm-prose-bar"
              >
                <span style="color: color-mix(in oklch, var(--telvm-shell-fg) 90%, transparent);">
                  {row.name}
                </span>
                <span style="color: var(--telvm-shell-muted);"> — </span>
                <span style="color: var(--telvm-shell-muted);">{row.note}</span>
              </li>
            </ul>
          </section>

          <section id="preflight-missing-list">
            <div
              class="text-[11px] uppercase tracking-wide mb-1"
              style="color: var(--telvm-shell-muted);"
            >
              not yet
            </div>
            <ul class="text-xs space-y-0.5 font-mono" style="color: var(--telvm-shell-muted);">
              <li>- Docker stats/events + push stream</li>
              <li>- ProxyPlug Finch → /app/… sandboxes</li>
              <li>- Runtime catalog (5 → 21+ images)</li>
              <li>- Sessions, Registry, HealthMonitor vitals UI</li>
            </ul>
          </section>
        </div>

        <div class="mt-6 lg:mt-0 min-w-0">
          <div
            class="text-[11px] uppercase tracking-wide mb-2"
            style="color: var(--telvm-shell-muted);"
          >
            agent API · FYI
          </div>
          <p class="text-xs mb-2" style="color: var(--telvm-shell-muted);">
            Markdown served from <code class="telvm-accent-dim-text">GET /telvm/api/fyi</code>
            — same origin as the control plane.
          </p>
          <iframe
            src={~p"/telvm/api/fyi"}
            class="w-full min-h-[24rem] rounded telvm-panel-border border bg-black/30"
            title="TELVM API FYI"
          />
        </div>
      </div>
    </div>
    """
  end

  # --- Helpers ---

  defp port_preview_active?(:http, src, m, p) when is_integer(p) and is_binary(src) do
    src == "/app/#{m.name}/port/#{p}/"
  end

  defp port_preview_active?(_, _, _, _), do: false

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

  defp warm_row_class(m, soak_s, pf_s) do
    active =
      (soak_s && soak_s.container_id == m.id) || (pf_s && pf_s.container_id == m.id)

    if active,
      do: "telvm-warm-row-active",
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
      do: "telvm-activity-live",
      else: "telvm-muted-xs"
  end

  defp soak_badge_txt(nil), do: "—"
  defp soak_badge_txt(%{soak: :ok}), do: "OK"
  defp soak_badge_txt(%{soak: :error}), do: "FAIL"
  defp soak_badge_txt(_), do: "—"

  defp soak_badge_class(nil), do: "telvm-muted-xs"
  defp soak_badge_class(%{soak: :ok}), do: "telvm-text-ok font-bold text-[10px]"
  defp soak_badge_class(%{soak: :error}), do: "telvm-text-danger-ink font-bold text-[10px]"
  defp soak_badge_class(_), do: "telvm-muted-xs"

  defp port_probe_txt(nil, _ports), do: "—"

  defp port_probe_txt(%{exposed_port: ep}, ports) when is_list(ports) and is_integer(ep) do
    if ep in ports, do: "OK", else: "!"
  end

  defp port_probe_txt(_, _), do: "—"

  defp port_probe_class(nil, _ports), do: "telvm-muted-xs"

  defp port_probe_class(%{exposed_port: ep}, ports) when is_list(ports) and is_integer(ep) do
    if ep in ports,
      do: "telvm-text-ok font-bold text-[10px]",
      else: "telvm-text-warn font-bold text-[10px]"
  end

  defp port_probe_class(_, _), do: "telvm-muted-xs"

  defp warm_status_class("running"), do: "telvm-text-ok"
  defp warm_status_class("paused"), do: "telvm-text-warn"
  defp warm_status_class("exited"), do: "telvm-muted-xs"
  defp warm_status_class(_), do: "telvm-muted-xs"

  # --- Nav ---

  attr :active, :atom, required: true

  defp terminal_nav(assigns) do
    ~H"""
    <nav class="flex flex-wrap gap-2 text-xs mb-4" aria-label="Companion views">
      <.link patch={~p"/warm"} class={nav_tab_class(@active, :warm_assets)}>Warm assets</.link>
      <.link patch={~p"/machines"} class={nav_tab_class(@active, :machines)}>Machines</.link>
      <.link patch={~p"/health"} class={nav_tab_class(@active, :preflight)}>Pre-flight</.link>
    </nav>
    """
  end

  defp nav_tab_class(active, tab) do
    on = active == tab

    [
      "px-2 py-0.5 border rounded-sm transition-colors",
      on && "telvm-nav-tab-active",
      !on && "telvm-nav-tab-idle"
    ]
  end

  # --- Shared components ---

  attr :cols, :list, required: true

  defp term_header(assigns) do
    ~H"""
    <div class="grid grid-cols-12 gap-x-2 px-2 py-1 text-[10px] sm:text-[11px] uppercase tracking-wide telvm-term-header">
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

  defp rollup_class(:ready), do: "telvm-rollup-ready"
  defp rollup_class(:degraded), do: "telvm-rollup-degraded"
  defp rollup_class(:blocked), do: "telvm-rollup-blocked"
  defp rollup_class(_), do: "telvm-accent-dim-text font-semibold"

  defp status_txt(:pass), do: "[ OK ]"
  defp status_txt(:fail), do: "[FAIL]"
  defp status_txt(:warn), do: "[WARN]"
  defp status_txt(:skip), do: "[SKIP]"
  defp status_txt(:info), do: "[INFO]"
  defp status_txt(_), do: "[ ?? ]"

  defp status_class(:pass), do: "telvm-status-pass"
  defp status_class(:fail), do: "telvm-status-fail"
  defp status_class(:warn), do: "telvm-status-warn"
  defp status_class(:skip), do: "telvm-status-skip"
  defp status_class(:info), do: "telvm-status-info"
  defp status_class(_), do: "telvm-accent-dim-text"
end
