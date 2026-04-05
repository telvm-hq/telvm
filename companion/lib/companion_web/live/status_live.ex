defmodule CompanionWeb.StatusLive do
  use CompanionWeb, :live_view

  alias Companion.Preflight
  alias Companion.StackStatus
  alias Companion.VmLifecycle
  alias Companion.VmLifecycle.Runner
  alias Companion.VmLifecycle.SoakRunner
  alias Companion.LabCatalog
  alias Companion.LabImageBuilder
  alias Companion.InferencePreflight
  alias Companion.InferenceChat
  alias Companion.GooseRuntime
  alias Companion.GooseHealth

  @default_entry LabCatalog.get(:cert_phoenix)
  @agent_chat_max_messages 40

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
      |> assign(:selected_catalog_entry, @default_entry)
      |> assign(:selected_telvm_certified, Map.get(@default_entry, :telvm_certified, false))
      |> assign(:destroying, false)
      |> assign(:warm_machines, [])
      |> assign(:compose_stack_snapshot, {:ok, []})
      |> assign(:soak_busy, false)
      |> assign(:soak_session, nil)
      |> assign(:preflight_session, nil)
      |> assign(:lab_readiness, %{})
      |> assign(:pending_soak_after_preflight, false)
      |> assign(:explorer_preview_id, nil)
      |> assign(:preview_iframe_src, nil)
      |> assign(:preview_mode, nil)
      |> assign(:warm_preview_panel, :iframe)
      |> assign(:warm_logs_text, nil)
      |> assign(:warm_logs_container_id, nil)
      |> assign(:warm_logs_loading, false)
      |> assign(:warm_logs_error, nil)
      |> assign(:lab_verify_tab, "status")
      |> assign(:verify_last_error, nil)
      |> assign(:verify_chain_active, false)
      |> assign(:lab_verify_pass, false)
      |> assign(:inference_base_url, inference_base_url_default())
      |> assign(:inference_api_key, "")
      |> assign(:inference_check_busy, false)
      |> assign(:inference_check_result, nil)
      |> assign(:inference_model_ids, [])
      |> assign(:agent_chat_session, :idle)
      |> assign(:agent_chat_model, nil)
      |> assign(:agent_chat_messages, [])
      |> assign(:agent_chat_busy, false)
      |> assign(:agent_chat_error, nil)
      |> assign(:agent_chat_tab, :goose)
      |> assign(:goose_chat_messages, [])
      |> assign(:goose_chat_busy, false)
      |> assign(:goose_chat_error, nil)
      |> assign(:goose_container_id, nil)
      |> assign(:goose_status, nil)
      |> assign(:goose_logs_text, nil)
      |> assign(:goose_logs_loading, false)
      |> assign(:goose_logs_error, nil)
      |> assign(:goose_health_snapshot, nil)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Companion.PubSub, Preflight.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, VmLifecycle.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, LabImageBuilder.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, SoakRunner.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, GooseHealth.topic())

      if socket.assigns.live_action == :agent_setup do
        send(self(), :load_goose_panel)
      end
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

        socket =
          if action == :warm_assets do
            assign(socket, :compose_stack_snapshot, fetch_compose_stack_snapshot())
          else
            socket
          end

        if connected?(socket), do: schedule_warm_refresh()
        {:noreply, socket}

      :agent_setup ->
        socket = assign(socket, :page_title, page_title(socket))

        if connected?(socket) do
          send(self(), :load_goose_panel)
          send(self(), :auto_connect_inference)
          GooseHealth.refresh()
        end

        {:noreply, socket}

      _ ->
        {:noreply, assign(socket, :page_title, page_title(socket))}
    end
  end

  defp page_title(socket) do
    case socket.assigns[:live_action] do
      :machines -> "Machines"
      :warm_assets -> "Warm assets"
      :agent_setup -> "Agent setup"
      _ -> "Pre-flight"
    end
  end

  defp inference_base_url_default do
    Application.get_env(:companion, :inference_base_url) ||
      Application.get_env(:companion, :default_inference_base_url) ||
      "http://host.docker.internal:11434/v1"
  end

  defp agent_default_model_name do
    Application.get_env(:companion, :agent_default_model) || "qwen2.5:0.5b"
  end

  defp pick_auto_chat_model(ids) when is_list(ids) do
    pref = agent_default_model_name() |> to_string() |> String.trim()

    cond do
      ids == [] ->
        nil

      pref != "" and pref in ids ->
        pref

      true ->
        Enum.find(ids, &String.contains?(&1, "qwen")) || List.first(ids)
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
      |> refresh_warm_machine_assigns()
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
      {:noreply, refresh_warm_machine_assigns(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:load_goose_panel, socket) do
    if socket.assigns.live_action == :agent_setup do
      {:noreply, load_goose_panel(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:auto_connect_inference, socket) do
    if socket.assigns.live_action != :agent_setup do
      {:noreply, socket}
    else
      base = socket.assigns.inference_base_url |> to_string() |> String.trim()
      key = socket.assigns.inference_api_key |> to_string()

      cond do
        base == "" ->
          {:noreply, socket}

        socket.assigns.inference_check_busy ->
          {:noreply, socket}

        true ->
          socket = assign(socket, :inference_check_busy, true)

          case InferencePreflight.check_models(base, api_key: key) do
            {:ok, meta} ->
              ids = Map.get(meta, :model_ids, [])

              socket =
                socket
                |> assign(:inference_check_busy, false)
                |> assign(:inference_check_result, {:ok, meta})
                |> assign(:inference_model_ids, ids)

              socket =
                if socket.assigns.agent_chat_session == :idle and ids != [] do
                  case pick_auto_chat_model(ids) do
                    nil ->
                      socket

                    model ->
                      socket
                      |> assign(:agent_chat_session, :active)
                      |> assign(:agent_chat_model, model)
                      |> assign(:agent_chat_messages, [])
                      |> assign(:agent_chat_error, nil)
                  end
                else
                  socket
                end

              {:noreply, socket}

            {:error, msg} when is_binary(msg) ->
              {:noreply,
               socket
               |> assign(:inference_check_busy, false)
               |> assign(:inference_check_result, {:error, msg})
               |> assign(:inference_model_ids, [])}
          end
      end
    end
  end

  def handle_info({:goose_health, snap}, socket) do
    if socket.assigns.live_action == :agent_setup do
      {:noreply, assign(socket, :goose_health_snapshot, snap)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:goose_chat_done, result}, socket) do
    if socket.assigns.live_action != :agent_setup do
      {:noreply, socket}
    else
      case result do
        {:ok, text} ->
          msgs =
            socket.assigns.goose_chat_messages ++ [%{"role" => "assistant", "content" => text}]

          msgs = trim_chat_messages(msgs, @agent_chat_max_messages)

          {:noreply,
           socket
           |> assign(:goose_chat_messages, msgs)
           |> assign(:goose_chat_busy, false)
           |> assign(:goose_chat_error, nil)}

        {:error, msg} when is_binary(msg) ->
          {:noreply,
           socket
           |> assign(:goose_chat_busy, false)
           |> assign(:goose_chat_error, msg)}
      end
    end
  end

  def handle_info({:agent_chat_done, result}, socket) do
    cond do
      socket.assigns.live_action != :agent_setup ->
        {:noreply, socket}

      socket.assigns.agent_chat_session != :active ->
        {:noreply, socket}

      true ->
        case result do
          {:ok, text} when is_binary(text) ->
            prev = socket.assigns.agent_chat_messages
            full = prev ++ [%{"role" => "assistant", "content" => text}]
            full = trim_chat_messages(full, @agent_chat_max_messages)

            {:noreply,
             socket
             |> assign(:agent_chat_messages, full)
             |> assign(:agent_chat_busy, false)
             |> assign(:agent_chat_error, nil)}

          {:error, msg} when is_binary(msg) ->
            {:noreply,
             socket
             |> assign(:agent_chat_busy, false)
             |> assign(:agent_chat_error, msg)}
        end
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
       |> assign(:selected_catalog_id, entry.id)
       |> assign(:selected_catalog_entry, entry)
       |> assign(:selected_telvm_certified, Map.get(entry, :telvm_certified, false))}
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
       |> assign(:selected_catalog_id, catalog_match.id)
       |> assign(:selected_catalog_entry, catalog_match)
       |> assign(:selected_telvm_certified, Map.get(catalog_match, :telvm_certified, false))}
    else
      {:noreply,
       socket
       |> assign(:selected_image, ref)
       |> assign(:selected_use_image_cmd, true)
       |> assign(:selected_container_cmd, nil)
       |> assign(:selected_catalog_id, nil)
       |> assign(:selected_catalog_entry, nil)
       |> assign(:selected_telvm_certified, false)}
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
  def handle_event("test_inference_endpoint", params, socket) do
    base = params |> Map.get("inference_base_url", "") |> to_string() |> String.trim()
    key = params |> Map.get("inference_api_key", "") |> to_string()

    socket =
      socket
      |> assign(:inference_base_url, base)
      |> assign(:inference_api_key, key)

    cond do
      base == "" ->
        {:noreply, assign(socket, :inference_check_result, {:error, "Enter a base URL."})}

      socket.assigns.inference_check_busy ->
        {:noreply, socket}

      true ->
        socket = assign(socket, :inference_check_busy, true)

        case InferencePreflight.check_models(base, api_key: key) do
          {:ok, meta} ->
            ids = Map.get(meta, :model_ids, [])

            {:noreply,
             socket
             |> assign(:inference_check_busy, false)
             |> assign(:inference_check_result, {:ok, meta})
             |> assign(:inference_model_ids, ids)}

          {:error, msg} when is_binary(msg) ->
            {:noreply,
             socket
             |> assign(:inference_check_busy, false)
             |> assign(:inference_check_result, {:error, msg})
             |> assign(:inference_model_ids, [])}
        end
    end
  end

  @impl true
  def handle_event("start_agent_chat", params, socket) do
    model = params |> Map.get("model", "") |> to_string() |> String.trim()

    cond do
      socket.assigns.agent_chat_session == :active ->
        {:noreply, socket}

      model == "" ->
        {:noreply, assign(socket, :agent_chat_error, "Choose or enter a model name.")}

      true ->
        {:noreply,
         socket
         |> assign(:agent_chat_session, :active)
         |> assign(:agent_chat_model, model)
         |> assign(:agent_chat_messages, [])
         |> assign(:agent_chat_error, nil)}
    end
  end

  @impl true
  def handle_event("send_agent_chat", params, socket) do
    content = params |> Map.get("content", "") |> to_string() |> String.trim()

    cond do
      socket.assigns.agent_chat_session != :active ->
        {:noreply, socket}

      socket.assigns.agent_chat_busy ->
        {:noreply, socket}

      content == "" ->
        {:noreply, socket}

      true ->
        base = socket.assigns.inference_base_url
        key = socket.assigns.inference_api_key
        locked = socket.assigns.agent_chat_model

        prev = socket.assigns.agent_chat_messages
        user_msgs = prev ++ [%{"role" => "user", "content" => content}]
        user_msgs = trim_chat_messages(user_msgs, @agent_chat_max_messages)

        parent = self()

        Task.start(fn ->
          result =
            try do
              InferenceChat.chat_completion(base, key, locked, user_msgs)
            rescue
              e -> {:error, Exception.message(e)}
            end

          send(parent, {:agent_chat_done, result})
        end)

        {:noreply,
         socket
         |> assign(:agent_chat_busy, true)
         |> assign(:agent_chat_error, nil)
         |> assign(:agent_chat_messages, user_msgs)}
    end
  end

  @impl true
  def handle_event("end_agent_chat", _params, socket) do
    {:noreply,
     socket
     |> assign(:agent_chat_session, :idle)
     |> assign(:agent_chat_model, nil)
     |> assign(:agent_chat_messages, [])
     |> assign(:agent_chat_error, nil)
     |> assign(:agent_chat_busy, false)}
  end

  @impl true
  def handle_event("set_agent_chat_tab", %{"tab" => tab}, socket)
      when tab in ["model", "goose"] do
    tab_atom =
      case tab do
        "goose" -> :goose
        _ -> :model
      end

    {:noreply, assign(socket, :agent_chat_tab, tab_atom)}
  end

  @impl true
  def handle_event("send_goose_chat", params, socket) do
    content = params |> Map.get("content", "") |> to_string() |> String.trim()

    cond do
      socket.assigns.live_action != :agent_setup ->
        {:noreply, socket}

      socket.assigns.goose_chat_busy ->
        {:noreply, socket}

      content == "" ->
        {:noreply, socket}

      is_nil(socket.assigns.goose_container_id) ->
        {:noreply,
         assign(
           socket,
           :goose_chat_error,
           "The Goose agent isn’t available yet. Add the goose service to Docker Compose, run the stack, then refresh this page."
         )}

      true ->
        cid = socket.assigns.goose_container_id

        msgs =
          trim_chat_messages(
            socket.assigns.goose_chat_messages ++ [%{"role" => "user", "content" => content}],
            @agent_chat_max_messages
          )

        parent = self()

        Task.start(fn ->
          result = GooseRuntime.run_text(cid, content)
          send(parent, {:goose_chat_done, result})
        end)

        {:noreply,
         socket
         |> assign(:goose_chat_messages, msgs)
         |> assign(:goose_chat_busy, true)
         |> assign(:goose_chat_error, nil)}
    end
  end

  @impl true
  def handle_event("clear_goose_chat", _params, socket) do
    if socket.assigns.live_action == :agent_setup do
      {:noreply,
       socket
       |> assign(:goose_chat_messages, [])
       |> assign(:goose_chat_error, nil)}
    else
      {:noreply, socket}
    end
  end

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

    socket = clear_warm_logs_preview(socket)

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
  def handle_event("certified_extended_soak", _params, socket) do
    ref = socket.assigns.selected_image

    cond do
      ref == "" ->
        {:noreply, put_flash(socket, :error, "Enter an image reference first.")}

      socket.assigns.selected_telvm_certified != true ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Certified soak applies to GHCR catalog chips only — select a “(certified)” lab or paste a matching ref."
         )}

      socket.assigns.soak_busy ->
        {:noreply, put_flash(socket, :error, "A soak monitor is already in progress.")}

      true ->
        overrides =
          socket.assigns
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

  @impl true
  def handle_event("set_lab_verify_tab", %{"tab" => tab}, socket)
      when tab in ["status", "errors"] do
    {:noreply, assign(socket, :lab_verify_tab, tab)}
  end

  @impl true
  def handle_event("preview_port", %{"path" => path}, socket) when is_binary(path) do
    {:noreply,
     socket
     |> clear_warm_logs_preview()
     |> assign(:preview_iframe_src, path)
     |> assign(:preview_mode, :http)
     |> assign(:explorer_preview_id, nil)}
  end

  @impl true
  def handle_event("show_warm_logs", %{"id" => id}, socket) when is_binary(id) do
    docker = Companion.Docker.impl()
    tail = 500

    socket =
      socket
      |> assign(:warm_preview_panel, :logs)
      |> assign(:warm_logs_container_id, id)
      |> assign(:warm_logs_loading, true)
      |> assign(:warm_logs_error, nil)
      |> assign(:warm_logs_text, nil)
      |> assign(:preview_iframe_src, nil)
      |> assign(:preview_mode, nil)
      |> assign(:explorer_preview_id, nil)

    case docker.container_logs(id, tail: tail) do
      {:ok, text} ->
        {:noreply,
         socket
         |> assign(:warm_logs_loading, false)
         |> assign(:warm_logs_text, warm_logs_with_preamble(id, text, :initial))}

      {:error, reason} ->
        {:noreply,
         socket
         |> assign(:warm_logs_loading, false)
         |> assign(:warm_logs_error, inspect(reason))}
    end
  end

  @impl true
  def handle_event("refresh_warm_logs", _params, socket) do
    id = socket.assigns[:warm_logs_container_id]
    tail = 500

    if is_nil(id) do
      {:noreply, socket}
    else
      docker = Companion.Docker.impl()

      socket =
        socket
        |> assign(:warm_logs_loading, true)
        |> assign(:warm_logs_error, nil)

      case docker.container_logs(id, tail: tail) do
        {:ok, text} ->
          {:noreply,
           socket
           |> assign(:warm_logs_loading, false)
           |> assign(:warm_logs_text, warm_logs_with_preamble(id, text, :refresh))}

        {:error, reason} ->
          {:noreply,
           socket
           |> assign(:warm_logs_loading, false)
           |> assign(:warm_logs_error, inspect(reason))}
      end
    end
  end

  @impl true
  def handle_event("refresh_goose_logs", _params, socket) do
    id = socket.assigns[:goose_container_id]
    tail = 200

    cond do
      socket.assigns.live_action != :agent_setup ->
        {:noreply, socket}

      is_nil(id) ->
        {:noreply, socket}

      true ->
        socket =
          socket
          |> assign(:goose_logs_loading, true)
          |> assign(:goose_logs_error, nil)

        case GooseRuntime.logs(id, tail: tail) do
          {:ok, text} ->
            {:noreply,
             socket
             |> assign(:goose_logs_loading, false)
             |> assign(:goose_logs_text, goose_logs_with_preamble(id, text, :refresh))}

          {:error, reason} ->
            {:noreply,
             socket
             |> assign(:goose_logs_loading, false)
             |> assign(:goose_logs_error, inspect(reason))}
        end
    end
  end

  @impl true
  def handle_event("restart_goose_container", _params, socket) do
    id = socket.assigns[:goose_container_id]

    cond do
      socket.assigns.live_action != :agent_setup ->
        {:noreply, socket}

      is_nil(id) ->
        {:noreply, put_flash(socket, :error, "Goose container not found.")}

      true ->
        case GooseRuntime.restart_container(id) do
          :ok ->
            socket =
              socket
              |> put_flash(:info, "Restarting Goose container #{String.slice(id, 0, 12)}…")
              |> load_goose_panel()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Goose restart failed: #{inspect(reason)}")}
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

  # --- Events: destroy individual machine (stop + remove) ---

  @impl true
  def handle_event("destroy_machine", %{"id" => cid}, socket) do
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
      |> put_flash(:info, "Destroying container #{String.slice(cid, 0, 12)}…")
      |> refresh_warm_machine_assigns()
      |> maybe_followup_warm_refresh()

    {:noreply, socket}
  end

  # --- Events: restart / pause / resume (Engine API via Docker adapter) ---

  @impl true
  def handle_event("restart_machine", %{"id" => cid}, socket) do
    docker = Companion.Docker.impl()

    case docker.container_restart(cid, timeout_sec: 10) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Restarting container #{String.slice(cid, 0, 12)}…")
          |> refresh_warm_machine_assigns()
          |> maybe_followup_warm_refresh()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Restart failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("pause_machine", %{"id" => cid}, socket) do
    docker = Companion.Docker.impl()

    case docker.container_pause(cid) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Pausing container #{String.slice(cid, 0, 12)}…")
          |> refresh_warm_machine_assigns()
          |> maybe_followup_warm_refresh()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Pause failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_event("unpause_machine", %{"id" => cid}, socket) do
    docker = Companion.Docker.impl()

    case docker.container_unpause(cid) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Resuming container #{String.slice(cid, 0, 12)}…")
          |> refresh_warm_machine_assigns()
          |> maybe_followup_warm_refresh()

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Resume failed: #{inspect(reason)}")}
    end
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
    entry =
      case assigns[:selected_catalog_id] do
        nil -> nil
        id -> LabCatalog.get(id)
      end

    overrides = [
      image: ref,
      use_image_default_cmd: assigns.selected_use_image_cmd
    ]

    overrides =
      if assigns[:selected_container_cmd] do
        Keyword.put(overrides, :container_cmd, assigns.selected_container_cmd)
      else
        overrides
      end

    env = entry && Map.get(entry, :container_env, [])

    if is_list(env) and env != [] do
      Keyword.put(overrides, :container_env, env)
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

      :agent_setup ->
        agent_setup(assigns)

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

  # --- Agent setup tab ---

  defp agent_setup(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />
      <div class="flex flex-wrap items-end justify-between gap-2 telvm-accent-border-b border-b pb-2 mb-4">
        <div class="text-[11px] sm:text-xs uppercase tracking-[0.2em] telvm-accent-text font-semibold">
          telvm · agent setup
        </div>
      </div>

      <p
        class="telvm-prose-bar text-[11px] mb-5 font-mono leading-relaxed max-w-2xl border-l-2 pl-2"
        style="color: var(--telvm-shell-muted);"
      >
        Ollama is probed when you open this tab; the
        <span class="telvm-accent-dim-text">Goose agent</span>
        tab is the default. The <span class="telvm-accent-dim-text">Model</span>
        tab starts a direct chat when models are listed (default model from <span class="font-mono telvm-accent-dim-text">TELVM_AGENT_DEFAULT_MODEL</span>).
        Weights live in your inference server, not in Phoenix.
      </p>

      <div class="lg:grid lg:grid-cols-2 lg:gap-4 lg:items-start">
        <div class="min-w-0 space-y-5 max-w-xl">
          <section
            class="rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4"
            id="agent-inference-preflight"
          >
            <form phx-submit="test_inference_endpoint" class="space-y-3">
              <div>
                <label
                  for="inference-base-url"
                  class="block telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] mb-1 font-semibold"
                >
                  OpenAI base URL
                </label>
                <input
                  type="text"
                  name="inference_base_url"
                  id="inference-base-url"
                  value={@inference_base_url}
                  autocomplete="off"
                  placeholder="http://host.docker.internal:11434/v1"
                  disabled={@inference_check_busy}
                  class="w-full px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring disabled:opacity-50"
                  style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                />
                <p class="text-[10px] mt-1" style="color: var(--telvm-shell-muted);">
                  Include <span class="font-mono telvm-accent-dim-text">/v1</span>
                  (or host only — /v1 is appended if missing). From Compose use
                  <span class="font-mono telvm-accent-dim-text">http://ollama:11434/v1</span>
                  when the inference service shares the stack network.
                </p>
              </div>

              <div>
                <label
                  for="inference-api-key"
                  class="block telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] mb-1 font-semibold"
                >
                  API key (optional)
                </label>
                <input
                  type="password"
                  name="inference_api_key"
                  id="inference-api-key"
                  value={@inference_api_key}
                  autocomplete="off"
                  placeholder="Bearer token if required"
                  disabled={@inference_check_busy}
                  class="w-full px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring disabled:opacity-50"
                  style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                />
              </div>

              <button
                type="submit"
                disabled={@inference_check_busy}
                class={[
                  "px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide",
                  @inference_check_busy && "cursor-not-allowed opacity-60 border-zinc-700",
                  !@inference_check_busy && "telvm-btn-primary"
                ]}
              >
                {if @inference_check_busy, do: "Refreshing…", else: "Refresh models"}
              </button>
            </form>

            <div :if={@inference_check_result != nil} class="mt-4 text-[11px] font-mono space-y-1">
              <%= case @inference_check_result do %>
                <% {:ok, meta} -> %>
                  <p class="telvm-text-ok font-medium">OK — models listed.</p>

                  <p style="color: var(--telvm-shell-muted);">Count: {meta.model_count}</p>

                  <p
                    :if={meta.sample_ids != []}
                    class="break-all"
                    style="color: var(--telvm-shell-muted);"
                  >
                    Sample: {Enum.join(meta.sample_ids, ", ")}
                  </p>
                <% {:error, msg} -> %>
                  <p class="telvm-text-danger-ink whitespace-pre-wrap">{msg}</p>
              <% end %>
            </div>
          </section>

          <aside
            class="min-w-0 rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4"
            id="agent-goose-panel"
          >
            <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.18em] mb-2 font-semibold">
              Agent runtime · diagnostics
            </div>
            <p class="text-[10px] mb-3" style="color: var(--telvm-shell-muted);">
              Optional: container state and log tail for operators. The Model / Goose chat panel is on the right on wide screens; use a full TTY for
              <span class="font-mono">goose session</span>
              when you need the interactive REPL.
            </p>
            <div class="text-[11px] font-mono space-y-1 mb-3">
              <p>
                <span class="telvm-accent-dim-text text-[10px] uppercase mr-1">container</span>
                {goose_panel_container_display(@goose_container_id)}
              </p>
              <p>
                <span class="telvm-accent-dim-text text-[10px] uppercase mr-1">state</span>
                {@goose_status || "—"}
              </p>
            </div>
            <p class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] mb-1 font-semibold">
              Exec (from repo root)
            </p>
            <pre
              class="text-[10px] font-mono whitespace-pre-wrap break-all p-2 rounded border mb-3"
              style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-input-bg) 88%, black); color: var(--telvm-shell-fg);"
            >docker compose exec -it goose goose session</pre>
            <div class="flex flex-wrap gap-2 mb-3">
              <button
                type="button"
                phx-click="refresh_goose_logs"
                phx-disable-with="refreshing…"
                disabled={@goose_container_id == nil}
                class={[
                  "px-2 py-1 text-[10px] font-mono rounded-md border uppercase tracking-wide",
                  @goose_container_id == nil && "cursor-not-allowed opacity-50 border-zinc-700",
                  @goose_container_id != nil && "telvm-btn-secondary"
                ]}
              >
                Refresh logs
              </button>
              <button
                :if={@goose_container_id != nil}
                type="button"
                phx-click="restart_goose_container"
                phx-disable-with="restarting…"
                class="px-2 py-1 text-[10px] font-mono rounded-md border uppercase tracking-wide telvm-btn-warn"
              >
                Restart
              </button>
            </div>
            <div class="text-[10px] mb-1 telvm-accent-dim-text uppercase tracking-wide">
              Engine logs (tail)
            </div>
            <code
              :if={@goose_logs_loading}
              class="block text-[10px] font-mono"
              style="color: var(--telvm-shell-muted);"
            >
              Loading…
            </code>
            <code
              :if={!@goose_logs_loading && @goose_logs_error}
              class="block text-[10px] font-mono text-red-400/90 whitespace-pre-wrap"
            >
              {@goose_logs_error}
            </code>
            <pre
              :if={!@goose_logs_loading && !@goose_logs_error}
              class="max-h-48 overflow-y-auto rounded border p-2 text-[10px] font-mono whitespace-pre-wrap break-words"
              style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-input-bg) 92%, black); color: var(--telvm-shell-fg);"
            >{@goose_logs_text || ""}</pre>
          </aside>

          <section class="text-[10px] leading-relaxed" style="color: var(--telvm-shell-muted);">
            <span class="telvm-accent-dim-text font-semibold uppercase tracking-[0.12em]">
              Weights
            </span>
            — Stored by your inference runtime (e.g. Ollama) in a Docker volume or host path; add an
            <span class="font-mono">ollama</span>
            Compose service when ready. Not loaded inside the Phoenix app.
          </section>
        </div>

        <div class="min-w-0">
          <section
            class="rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4 lg:sticky lg:top-4"
            id="agent-chat-panel"
          >
            <div class="flex flex-wrap items-center justify-between gap-2 mb-3">
              <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.18em] font-semibold">
                Chat
              </div>
              <div
                class="inline-flex rounded border text-[10px] font-mono overflow-hidden"
                style="border-color: var(--telvm-shell-border);"
                role="tablist"
              >
                <button
                  type="button"
                  phx-click="set_agent_chat_tab"
                  phx-value-tab="model"
                  role="tab"
                  aria-selected={@agent_chat_tab == :model}
                  class={agent_chat_tab_btn_class(@agent_chat_tab == :model)}
                >
                  Model
                </button>
                <button
                  type="button"
                  phx-click="set_agent_chat_tab"
                  phx-value-tab="goose"
                  role="tab"
                  aria-selected={@agent_chat_tab == :goose}
                  class={agent_chat_tab_btn_class(@agent_chat_tab == :goose)}
                >
                  Goose agent
                </button>
              </div>
            </div>

            <div class={["space-y-3", @agent_chat_tab != :model && "hidden"]}>
              <p class="text-[10px]" style="color: var(--telvm-shell-muted);">
                Direct OpenAI-style completions. One session at a time — end the session to switch models. Transcript is ephemeral.
              </p>

              <div :if={@agent_chat_session == :idle} class="space-y-2">
                <form phx-submit="start_agent_chat" class="space-y-2">
                  <div :if={@inference_model_ids != []}>
                    <label
                      for="agent-chat-model-select"
                      class="block telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] mb-1 font-semibold"
                    >
                      Model
                    </label>
                    <select
                      name="model"
                      id="agent-chat-model-select"
                      class="w-full px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring"
                      style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                    >
                      <option value="" disabled selected class="text-zinc-500">
                        — pick after Refresh models —
                      </option>
                      <option :for={id <- @inference_model_ids} value={id}>{id}</option>
                    </select>
                  </div>

                  <div :if={@inference_model_ids == []}>
                    <label
                      for="agent-chat-model-text"
                      class="block telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] mb-1 font-semibold"
                    >
                      Model name
                    </label>
                    <input
                      type="text"
                      name="model"
                      id="agent-chat-model-text"
                      autocomplete="off"
                      placeholder="e.g. tinyllama"
                      class="w-full px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring"
                      style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                    />
                    <p class="text-[10px] mt-1" style="color: var(--telvm-shell-muted);">
                      Run <span class="font-mono telvm-accent-dim-text">Refresh models</span>
                      to fill the list, or type a model id from your server.
                    </p>
                  </div>

                  <p
                    :if={@agent_chat_error != nil && @agent_chat_session == :idle}
                    class="text-[11px] telvm-text-danger-ink"
                  >
                    {@agent_chat_error}
                  </p>

                  <button
                    type="submit"
                    class="px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide telvm-btn-secondary"
                  >
                    Start session
                  </button>
                </form>
              </div>

              <div :if={@agent_chat_session == :active} class="space-y-2">
                <div class="flex flex-wrap items-center justify-between gap-2">
                  <p class="text-[11px] font-mono" style="color: var(--telvm-shell-fg);">
                    <span class="telvm-accent-dim-text text-[10px] uppercase mr-1">model</span>
                    {@agent_chat_model}
                  </p>
                  <button
                    type="button"
                    phx-click="end_agent_chat"
                    class="px-2 py-1 text-[10px] font-mono rounded-md border uppercase tracking-wide telvm-btn-warn"
                  >
                    End session
                  </button>
                </div>

                <pre
                  class="max-h-48 overflow-y-auto rounded border p-2 text-[11px] font-mono whitespace-pre-wrap break-words"
                  style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-input-bg) 92%, black); color: var(--telvm-shell-fg);"
                ><%= agent_chat_transcript(@agent_chat_messages) %></pre>

                <div
                  :if={@agent_chat_busy}
                  class="text-[10px] telvm-accent-dim-text animate-pulse"
                >
                  Model is replying…
                </div>

                <p
                  :if={@agent_chat_error != nil}
                  class="text-[11px] telvm-text-danger-ink whitespace-pre-wrap"
                >
                  {@agent_chat_error}
                </p>

                <form phx-submit="send_agent_chat" class="space-y-2">
                  <textarea
                    name="content"
                    rows="3"
                    placeholder="Message…"
                    disabled={@agent_chat_busy}
                    class="w-full px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring disabled:opacity-50"
                    style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                  ></textarea>
                  <button
                    type="submit"
                    disabled={@agent_chat_busy}
                    class={[
                      "px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide",
                      @agent_chat_busy && "cursor-not-allowed opacity-60 border-zinc-700",
                      !@agent_chat_busy && "telvm-btn-primary"
                    ]}
                  >
                    {if @agent_chat_busy, do: "Sending…", else: "Send"}
                  </button>
                </form>
              </div>
            </div>

            <div class={["space-y-3", @agent_chat_tab != :goose && "hidden"]} id="agent-goose-chat">
              <p class="text-[10px]" style="color: var(--telvm-shell-muted);">
                Messages go to the Goose process in your stack (configured with Ollama). Streaming may arrive later; for now each send runs one agent turn.
              </p>
              <p
                id="agent-goose-health-line"
                class="text-[9px] font-mono leading-snug rounded border px-2 py-1.5"
                style="border-color: var(--telvm-shell-border); color: var(--telvm-shell-muted); background: color-mix(in oklch, var(--telvm-input-bg) 88%, black);"
              >
                {goose_health_line(@goose_health_snapshot)}
              </p>

              <div
                class="space-y-2 min-h-[10rem] max-h-[min(50vh,22rem)] overflow-y-auto rounded border p-3 text-[11px] font-mono leading-relaxed"
                style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-input-bg) 94%, black);"
              >
                <div
                  :if={@goose_chat_messages == [] && !@goose_chat_busy}
                  class="text-[10px] italic"
                  style="color: var(--telvm-shell-muted);"
                >
                  Say hello — you should get a reply once Goose is running and configured.
                </div>
                <div :for={m <- @goose_chat_messages} class={goose_chat_row_class(m)}>
                  <div class="text-[9px] uppercase tracking-wide mb-0.5 telvm-accent-dim-text">
                    {goose_chat_role_label(m)}
                  </div>
                  <div class="whitespace-pre-wrap break-words">{m["content"]}</div>
                </div>
                <div :if={@goose_chat_busy} class="text-[10px] telvm-accent-dim-text animate-pulse">
                  Goose is thinking…
                </div>
              </div>

              <p
                :if={@goose_chat_error != nil}
                class="text-[11px] telvm-text-danger-ink whitespace-pre-wrap"
              >
                {@goose_chat_error}
              </p>

              <div class="flex flex-wrap gap-2">
                <button
                  :if={@goose_chat_messages != []}
                  type="button"
                  phx-click="clear_goose_chat"
                  class="px-2 py-1 text-[10px] font-mono rounded-md border uppercase tracking-wide telvm-btn-secondary"
                >
                  Clear
                </button>
              </div>

              <form phx-submit="send_goose_chat" class="space-y-2">
                <textarea
                  name="content"
                  rows="3"
                  placeholder="Message the Goose agent…"
                  disabled={@goose_chat_busy || @goose_container_id == nil}
                  class="w-full px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring disabled:opacity-50"
                  style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                ></textarea>
                <button
                  type="submit"
                  disabled={@goose_chat_busy || @goose_container_id == nil}
                  class={[
                    "px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide",
                    (@goose_chat_busy || @goose_container_id == nil) &&
                      "cursor-not-allowed opacity-60 border-zinc-700",
                    !@goose_chat_busy && @goose_container_id != nil && "telvm-btn-primary"
                  ]}
                >
                  {if @goose_chat_busy, do: "Sending…", else: "Send"}
                </button>
              </form>
            </div>
          </section>
        </div>
      </div>
    </div>
    """
  end

  defp agent_chat_transcript(messages) when is_list(messages) do
    messages
    |> Enum.map(fn
      %{"role" => r, "content" => c} ->
        "[#{r}] #{c}"

      _ ->
        ""
    end)
    |> Enum.join("\n\n")
  end

  defp agent_chat_tab_btn_class(true),
    do:
      "px-3 py-1.5 telvm-btn-primary border-0 rounded-none first:rounded-l last:rounded-r outline-none focus-visible:ring-1 focus-visible:ring-offset-0"

  defp agent_chat_tab_btn_class(false),
    do:
      "px-3 py-1.5 rounded-none first:rounded-l last:rounded-r border-0 bg-black/25 text-[var(--telvm-shell-muted)] hover:text-[var(--telvm-shell-fg)] outline-none focus-visible:ring-1"

  defp goose_chat_role_label(%{"role" => "user"}), do: "You"
  defp goose_chat_role_label(%{"role" => "assistant"}), do: "Goose"
  defp goose_chat_role_label(_), do: "—"

  defp goose_chat_row_class(%{"role" => "user"}),
    do: "rounded-md border border-zinc-700/60 bg-black/20 px-2 py-2"

  defp goose_chat_row_class(%{"role" => "assistant"}),
    do: "rounded-md border border-zinc-600/40 bg-black/35 px-2 py-2"

  defp goose_chat_row_class(_), do: "px-2 py-2"

  defp goose_health_line(nil) do
    "Goose health: land here with the stack running; probes run periodically and when you open Agent setup."
  end

  defp goose_health_line(%Companion.GooseHealth.Snapshot{} = s) do
    ts = Calendar.strftime(s.checked_at, "%H:%M:%S UTC")
    c = goose_health_container_txt(s.container)
    b = goose_health_step_txt(s.binary)
    o = goose_health_step_txt(s.ollama)
    a = goose_health_agent_txt(s.agent_run)

    "Last check #{ts} · #{c} · binary #{b} · Ollama #{o} · hello #{a}"
  end

  defp goose_health_container_txt({:ok, id}) when is_binary(id) do
    "ctr " <> String.slice(id, 0, 8) <> "…"
  end

  defp goose_health_container_txt({:error, :not_found}), do: "no Goose svc"
  defp goose_health_container_txt({:error, other}), do: "ctr " <> inspect(other)

  defp goose_health_step_txt(:ok), do: "OK"
  defp goose_health_step_txt(:skipped), do: "—"

  defp goose_health_step_txt({:error, msg}) do
    "ERR " <> String.slice(to_string(msg), 0, 56)
  end

  defp goose_health_agent_txt(:skipped), do: "—"
  defp goose_health_agent_txt(:ok), do: "OK"

  defp goose_health_agent_txt({:error, msg}) do
    "ERR " <> String.slice(to_string(msg), 0, 44)
  end

  defp trim_chat_messages(msgs, max) when is_list(msgs) and max > 0 do
    if length(msgs) <= max, do: msgs, else: Enum.take(msgs, -max)
  end

  # --- Warm assets tab ---

  defp warm_assets(assigns) do
    blueprint =
      Companion.Topology.Ascii.warm_blueprint(
        assigns.warm_machines,
        assigns.compose_stack_snapshot
      )

    assigns = assign(assigns, :warm_network_blueprint, blueprint)

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

      <section
        class="mt-6 pt-4 telvm-accent-border-b border-t border-dashed"
        aria-labelledby="warm-network-blueprint-heading"
      >
        <h2
          id="warm-network-blueprint-heading"
          class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.15em] mb-2 font-semibold"
        >
          Network blueprint
        </h2>

        <p class="text-[9px] font-mono mb-3" style="color: var(--telvm-shell-muted);">
          Live snapshot: Compose stack (from Engine) + lab VMs (this tab). Refreshes with the warm list.
        </p>
        <pre
          class="telvm-panel-bg telvm-panel-border border rounded-sm p-3 w-full text-[10px] sm:text-[11px] font-mono whitespace-pre overflow-x-auto"
          aria-label="Network blueprint: Compose stack, Docker bridge, and warm lab containers"
        ><%= @warm_network_blueprint %></pre>
      </section>
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
        No warm machines — run verify or certified soak on Machines, or leave a lab container up.
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
              <div :if={warm_machine_running?(m)} class="flex flex-wrap items-center gap-1">
                <button
                  type="button"
                  phx-click="restart_machine"
                  phx-value-id={m.id}
                  phx-disable-with="restarting…"
                  class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-secondary"
                >
                  restart
                </button>
                <button
                  type="button"
                  phx-click="pause_machine"
                  phx-value-id={m.id}
                  phx-disable-with="pausing…"
                  class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-warn"
                >
                  pause
                </button>
              </div>

              <div :if={warm_machine_paused?(m)} class="flex flex-wrap items-center gap-1">
                <button
                  type="button"
                  phx-click="unpause_machine"
                  phx-value-id={m.id}
                  phx-disable-with="resuming…"
                  class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-secondary"
                >
                  resume
                </button>
                <button
                  type="button"
                  phx-click="destroy_machine"
                  phx-value-id={m.id}
                  phx-disable-with="destroying…"
                  class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-danger"
                >
                  destroy
                </button>
              </div>

              <div :if={warm_machine_destroy_only?(m)} class="flex flex-wrap items-center gap-1">
                <button
                  type="button"
                  phx-click="destroy_machine"
                  phx-value-id={m.id}
                  phx-disable-with="destroying…"
                  class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-danger"
                >
                  destroy
                </button>
              </div>
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
                phx-click="show_warm_logs"
                phx-value-id={m.id}
                class={[
                  "inline-flex items-center gap-1 px-2 py-1 rounded-md border text-xs font-mono transition-colors",
                  logs_preview_active?(@warm_preview_panel, @warm_logs_container_id, m.id) &&
                    "telvm-files-btn-on",
                  !logs_preview_active?(@warm_preview_panel, @warm_logs_container_id, m.id) &&
                    "telvm-files-btn-off"
                ]}
              >
                <.icon name="hero-command-line" class="size-3.5" /> logs
              </button>
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
      <div :if={@warm_preview_panel == :logs} class="flex flex-col flex-1 min-h-0 gap-2">
        <div class="flex flex-wrap items-center justify-between gap-2 shrink-0">
          <div
            class="text-[10px] uppercase tracking-wide font-semibold"
            style="color: var(--telvm-shell-muted);"
          >
            logs
          </div>

          <button
            type="button"
            phx-click="refresh_warm_logs"
            class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-secondary"
            phx-disable-with="refreshing…"
          >
            refresh
          </button>
        </div>
        <pre
          class="telvm-warm-preview-frame w-full flex-1 min-h-[12rem] max-h-[min(82vh,44rem)] overflow-auto rounded border bg-black/50 p-3 whitespace-pre-wrap font-mono text-[11px] leading-relaxed"
          style="border-color: var(--telvm-shell-border); color: var(--telvm-shell-fg);"
        ><code
            :if={@warm_logs_loading}
            class="block"
            style="color: var(--telvm-shell-muted);"
          >Loading…</code><code :if={!@warm_logs_loading && @warm_logs_error} class="block text-red-400/90">{@warm_logs_error}</code><code
            :if={!@warm_logs_loading && !@warm_logs_error}
            class="block whitespace-pre-wrap"
          >{@warm_logs_text || ""}</code></pre>
      </div>

      <div :if={@warm_preview_panel != :logs} class="flex flex-col flex-1 min-h-0">
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

          <p
            class="text-[11px] max-w-sm leading-relaxed mb-3"
            style="color: var(--telvm-shell-muted);"
          >
            Choose a published port (for example
            <span class="telvm-accent-dim-text font-mono">:3333</span>
            on the default Node image), open <span class="telvm-accent-dim-text font-mono">logs</span>
            for stdout/stderr, or <span class="telvm-accent-dim-text font-mono">files</span>
            for the Monaco editor.
          </p>

          <p class="text-[10px] font-mono opacity-70" style="color: var(--telvm-shell-muted);">
            The frame stays here so layout matches when a preview is active.
          </p>
        </div>
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
          class="grid gap-3 mb-4 justify-start [grid-template-columns:repeat(auto-fill,minmax(132px,1fr))]"
          id="lab-catalog-grid"
        >
          <div :for={entry <- @lab_catalog} class="flex max-w-[152px] flex-col gap-1.5 shrink-0">
            <button
              type="button"
              phx-click="select_image"
              phx-value-id={entry.id}
              class={[
                "w-full min-w-0 rounded-lg border text-left transition-all p-2 min-h-[5.25rem] flex flex-col items-stretch justify-center",
                "bg-white border-zinc-300 shadow-[0_1px_3px_rgba(15,23,42,0.07)]",
                "hover:border-zinc-400 hover:shadow-md hover:bg-zinc-50/90",
                @selected_catalog_id == entry.id &&
                  "ring-2 ring-[color-mix(in_oklch,var(--telvm-accent)_50%,transparent)] border-[color-mix(in_oklch,var(--telvm-accent)_38%,transparent)] bg-zinc-100 shadow-[0_2px_8px_rgba(15,23,42,0.12)]",
                @selected_catalog_id != entry.id && "border-zinc-300"
              ]}
            >
              <span class="block w-full rounded-md bg-white">
                <img
                  src={~p"/images/lab-stacks/#{entry.stack_card}"}
                  alt={entry.label}
                  class="w-full h-[4.25rem] object-contain object-center rounded-sm pointer-events-none select-none"
                  loading="lazy"
                  decoding="async"
                />
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

        <section
          :if={@selected_catalog_entry}
          id="lab-stack-disclosure"
          data-catalog-id={@selected_catalog_entry.id}
          class="mb-5 max-w-3xl rounded-md border p-3 sm:p-4"
          style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-panel-bg) 88%, white);"
          aria-labelledby="lab-stack-disclosure-heading"
        >
          <h3
            id="lab-stack-disclosure-heading"
            class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.15em] font-semibold mb-2"
          >
            stack disclosure
            <span class="font-mono normal-case opacity-80" style="color: var(--telvm-shell-muted);">
              (local pull not required to read this)
            </span>
          </h3>

          <p class="text-[10px] mb-2 leading-snug" style="color: var(--telvm-shell-muted);">
            Key=value lines below are for humans and automation (agents); they summarize what this certified image contains and why it matches common production practice for the language.
          </p>

          <div
            class="rounded border p-2 mb-3 font-mono text-[10px] sm:text-[11px] leading-relaxed whitespace-pre-wrap overflow-x-auto"
            style="border-color: color-mix(in oklch, var(--telvm-shell-border) 85%, transparent); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
            role="region"
            aria-label="Installed components and versions"
          >
            {@selected_catalog_entry.stack_disclosure}
          </div>

          <h4 class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] font-semibold mb-1.5">
            why this shape (best practice)
          </h4>

          <p
            class="text-[11px] sm:text-xs leading-relaxed max-w-prose"
            style="color: var(--telvm-shell-muted);"
          >
            {@selected_catalog_entry.best_practice}
          </p>
        </section>

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
                phx-click="certified_extended_soak"
                disabled={@soak_busy or @vm_preflight_busy or not @selected_telvm_certified}
                title={
                  if(@selected_telvm_certified,
                    do: "60s stability window for GHCR telvm-lab-* images",
                    else: "Select a certified catalog chip (GHCR) first"
                  )
                }
                class={[
                  "px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide",
                  (@soak_busy or @vm_preflight_busy or not @selected_telvm_certified) &&
                    "cursor-not-allowed opacity-60 border-zinc-700",
                  !(@soak_busy or @vm_preflight_busy or not @selected_telvm_certified) &&
                    "telvm-btn-secondary"
                ]}
                style={
                  if(@soak_busy or @vm_preflight_busy or not @selected_telvm_certified,
                    do: "color: var(--telvm-shell-muted)",
                    else: nil
                  )
                }
              >
                Certified soak (60s)
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
            <span class="tabular-nums mr-2 opacity-70">{Calendar.strftime(ts, "%H:%M:%S UTC")}</span>
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

  defp logs_preview_active?(:logs, container_id, row_id)
       when is_binary(container_id) and is_binary(row_id) do
    container_id == row_id
  end

  defp logs_preview_active?(_, _, _), do: false

  defp warm_logs_display_id(id) when is_binary(id) do
    id = String.trim(id)

    if String.length(id) > 12 do
      String.slice(id, 0, 12) <> "…"
    else
      id
    end
  end

  defp goose_panel_container_display(nil), do: "—"
  defp goose_panel_container_display(id) when is_binary(id), do: warm_logs_display_id(id)

  defp warm_logs_preamble(container_id, kind) when kind in [:initial, :refresh] do
    label =
      case kind do
        :initial -> "Connected to your container logs"
        :refresh -> "Refreshed container logs"
      end

    ts =
      DateTime.utc_now()
      |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")

    "#{label} · container #{warm_logs_display_id(container_id)}\n#{ts}\n\n"
  end

  defp warm_logs_with_preamble(container_id, raw_text, kind) do
    warm_logs_preamble(container_id, kind) <> (raw_text || "")
  end

  defp goose_logs_preamble(container_id, kind) when kind in [:initial, :refresh] do
    label =
      case kind do
        :initial -> "Goose container logs (initial)"
        :refresh -> "Goose container logs (refresh)"
      end

    ts =
      DateTime.utc_now()
      |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")

    "#{label} · container #{warm_logs_display_id(container_id)}\n#{ts}\n\n"
  end

  defp goose_logs_with_preamble(container_id, raw_text, kind) do
    goose_logs_preamble(container_id, kind) <> (raw_text || "")
  end

  defp load_goose_panel(socket) do
    socket =
      socket
      |> assign(:goose_logs_loading, true)
      |> assign(:goose_logs_error, nil)

    case GooseRuntime.find_container() do
      {:ok, id, status} ->
        case GooseRuntime.logs(id, tail: 200) do
          {:ok, text} ->
            socket
            |> assign(:goose_container_id, id)
            |> assign(:goose_status, status)
            |> assign(:goose_logs_text, goose_logs_with_preamble(id, text, :initial))
            |> assign(:goose_logs_loading, false)

          {:error, reason} ->
            socket
            |> assign(:goose_container_id, id)
            |> assign(:goose_status, status)
            |> assign(:goose_logs_text, nil)
            |> assign(:goose_logs_loading, false)
            |> assign(:goose_logs_error, inspect(reason))
        end

      {:error, :not_found} ->
        socket
        |> assign(:goose_container_id, nil)
        |> assign(:goose_status, "not found")
        |> assign(:goose_logs_text, nil)
        |> assign(:goose_logs_loading, false)

      {:error, reason} ->
        socket
        |> assign(:goose_container_id, nil)
        |> assign(:goose_status, "error")
        |> assign(:goose_logs_text, nil)
        |> assign(:goose_logs_loading, false)
        |> assign(:goose_logs_error, inspect(reason))
    end
  end

  defp clear_warm_logs_preview(socket) do
    socket
    |> assign(:warm_preview_panel, :iframe)
    |> assign(:warm_logs_text, nil)
    |> assign(:warm_logs_container_id, nil)
    |> assign(:warm_logs_loading, false)
    |> assign(:warm_logs_error, nil)
  end

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

  defp refresh_warm_machine_assigns(socket) do
    socket =
      socket
      |> assign(:warm_machines, fetch_warm_machines())

    if socket.assigns.live_action == :warm_assets do
      assign(socket, :compose_stack_snapshot, fetch_compose_stack_snapshot())
    else
      socket
    end
  end

  defp fetch_compose_stack_snapshot do
    docker = Companion.Docker.impl()

    case docker.container_list(filters: %{"label" => ["com.docker.compose.project=telvm"]}) do
      {:ok, containers} ->
        {:ok, Enum.map(containers, &extract_compose_stack_item/1)}

      {:error, _} ->
        {:error, :unavailable}
    end
  end

  defp extract_compose_stack_item(c) do
    labels = c["Labels"] || %{}

    service =
      Map.get(labels, "com.docker.compose.service") ||
        Map.get(labels, :"com.docker.compose.service") ||
        "?"

    name =
      case c["Names"] do
        [n | _] -> String.trim_leading(n, "/")
        _ -> String.slice(c["Id"] || "", 0, 12)
      end

    %{
      service: service,
      name: name,
      state: normalize_warm_list_state(c),
      id: c["Id"] || ""
    }
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
      status: normalize_warm_list_state(c),
      created: c["Created"]
    }
  end

  defp normalize_warm_list_state(c) when is_map(c) do
    case c["State"] do
      s when is_binary(s) and s != "" ->
        String.downcase(String.trim(s))

      _ ->
        case c["Status"] do
          s when is_binary(s) ->
            st = String.downcase(String.trim(s))

            cond do
              String.starts_with?(st, "up ") and String.contains?(st, "paused") -> "paused"
              String.starts_with?(st, "up ") -> "running"
              st == "paused" or String.contains?(st, "paused") -> "paused"
              String.starts_with?(st, "exited") -> "exited"
              true -> st
            end

          _ ->
            "unknown"
        end
    end
  end

  defp warm_machine_running?(m), do: m.status == "running"
  defp warm_machine_paused?(m), do: m.status == "paused"

  defp warm_machine_destroy_only?(m),
    do: not warm_machine_running?(m) and not warm_machine_paused?(m)

  defp maybe_followup_warm_refresh(socket) do
    if connected?(socket), do: Process.send_after(self(), :refresh_warm_machines, 500)
    socket
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
      <.link patch={~p"/agent"} class={nav_tab_class(@active, :agent_setup)}>Agent setup</.link>
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
