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
  alias Companion.NetworkAgentPoller
  alias Companion.EgressProxy
  alias Companion.ClosedAgents.Catalog, as: ClosedAgentsCatalog
  alias Companion.ClosedAgentWarmRegistry
  alias Companion.MorayeelRunner
  alias Companion.Morayeel.OperatorGuide
  alias Companion.SavedLabImages

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
      |> assign(:network_agent_snapshot, nil)
      |> assign(:egress_proxy_snapshot, EgressProxy.snapshot())
      |> assign(:fyi_expanded, false)
      |> assign(:retardeel_verify_status, :idle)
      |> assign(:retardeel_verify_results, nil)
      |> assign(:other_agents_rows, [])
      |> assign(:other_agents_verify_busy, false)
      |> assign(:other_agents_verify_service, nil)
      |> assign(:other_agents_verify_error, nil)
      |> assign(:saved_pull_refs, SavedLabImages.list_refs_for_chips())
      |> assign(:closed_agents_tab, "claude")
      |> assign(:morayeel, MorayeelRunner.snapshot())
      |> assign(:morayeel_operator_guide, OperatorGuide.data())

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Companion.PubSub, Preflight.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, VmLifecycle.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, LabImageBuilder.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, SoakRunner.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, GooseHealth.topic())

      Phoenix.PubSub.subscribe(Companion.PubSub, NetworkAgentPoller.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, EgressProxy.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, Companion.RetardeelVerifier.topic())
      Phoenix.PubSub.subscribe(Companion.PubSub, MorayeelRunner.topic())

      if socket.assigns.live_action == :oss_agents do
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
        socket = assign(socket, :warm_machines, fetch_warm_machines_merged())

        socket =
          if action == :warm_assets do
            assign(socket, :compose_stack_snapshot, fetch_compose_stack_snapshot())
          else
            socket
            |> assign(:saved_pull_refs, SavedLabImages.list_refs_for_chips())
            |> assign(:other_agents_rows, fetch_other_agents_rows())
          end

        if connected?(socket), do: schedule_warm_refresh()
        {:noreply, socket}

      :oss_agents ->
        socket = assign(socket, :page_title, page_title(socket))

        if connected?(socket) do
          send(self(), :load_goose_panel)
          send(self(), :auto_connect_inference)
          GooseHealth.refresh()
        end

        {:noreply, socket}

      :morayeel ->
        {:noreply, assign(socket, :page_title, page_title(socket))}

      _ ->
        {:noreply, assign(socket, :page_title, page_title(socket))}
    end
  end

  defp page_title(socket) do
    case socket.assigns[:live_action] do
      :machines -> "Machines"
      :warm_assets -> "Warm assets"
      :oss_agents -> "OSS Agents"
      :morayeel -> "Morayeel"
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
  defp mission_tab?(:morayeel), do: true
  defp mission_tab?(_), do: false

  # --- PubSub handlers ---

  @impl true
  def handle_info({:report, report}, socket) do
    {:noreply, assign(socket, :report, report)}
  end

  def handle_info({:network_agent_snapshot, snapshot}, socket) when is_map(snapshot) do
    {:noreply, assign(socket, :network_agent_snapshot, snapshot)}
  end

  def handle_info({:egress_deny, _payload}, socket) do
    {:noreply, assign(socket, :egress_proxy_snapshot, EgressProxy.snapshot())}
  end

  def handle_info({:closed_agent_verify_done, service, cid, {:ok, :verified}}, socket) do
    ClosedAgentWarmRegistry.register_verified(cid)

    socket =
      socket
      |> assign(:other_agents_verify_busy, false)
      |> assign(:other_agents_verify_service, nil)
      |> assign(:other_agents_verify_error, nil)
      |> assign(:other_agents_rows, fetch_other_agents_rows())
      |> put_flash(:info, "#{service}: basic egress soak passed — see Warm assets")
      |> refresh_warm_machine_assigns()
      |> maybe_followup_warm_refresh()

    {:noreply, socket}
  end

  def handle_info({:closed_agent_verify_done, service, _cid, {:error, step, msg}}, socket) do
    err = "#{service} basic soak failed (#{step}): #{msg}"

    {:noreply,
     socket
     |> assign(:other_agents_verify_busy, false)
     |> assign(:other_agents_verify_service, nil)
     |> assign(:other_agents_verify_error, err)
     |> assign(:other_agents_rows, fetch_other_agents_rows())}
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

  def handle_info({:image_pull_done, ref, result}, socket) do
    socket =
      socket
      |> assign(:image_pull_busy, false)
      |> assign(:lab_catalog, LabCatalog.with_availability())

    socket =
      case result do
        :ok ->
          socket = put_flash(socket, :info, "Image pulled successfully.")

          case SavedLabImages.record_pull(ref) do
            {:ok, _} ->
              assign(socket, :saved_pull_refs, SavedLabImages.list_refs_for_chips())

            {:error, changeset} ->
              msg =
                changeset.errors
                |> Enum.map(fn {f, {m, _}} -> "#{f} #{m}" end)
                |> Enum.join("; ")

              socket
              |> assign(:saved_pull_refs, SavedLabImages.list_refs_for_chips())
              |> put_flash(:error, "Could not save image ref for reuse: #{msg}")
          end

        {:error, reason} ->
          put_flash(socket, :error, "Pull failed: #{inspect(reason)}")
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
    if socket.assigns.live_action == :oss_agents do
      {:noreply, load_goose_panel(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:auto_connect_inference, socket) do
    if socket.assigns.live_action != :oss_agents do
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
    if socket.assigns.live_action == :oss_agents do
      {:noreply, assign(socket, :goose_health_snapshot, snap)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:retardeel_verify, payload}, socket) do
    if socket.assigns.live_action == :oss_agents do
      {:noreply,
       socket
       |> assign(:retardeel_verify_status, payload.status)
       |> assign(:retardeel_verify_results, payload.results)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:morayeel_run, payload}, socket) do
    snap = MorayeelRunner.snapshot()

    socket =
      socket
      |> assign(:morayeel, snap)
      |> then(fn s ->
        case payload do
          %{event: :rejected, message: msg} when is_binary(msg) ->
            put_flash(s, :error, msg)

          %{event: :finished} ->
            cond do
              snap.status == :passed ->
                put_flash(s, :info, "Morayeel run #{snap.run_id} passed")

              snap.status == :failed ->
                put_flash(s, :error, snap.error || "Morayeel run failed")

              true ->
                s
            end

          _ ->
            s
        end
      end)

    {:noreply, socket}
  end

  def handle_info({:goose_chat_done, result}, socket) do
    if socket.assigns.live_action != :oss_agents do
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
      socket.assigns.live_action != :oss_agents ->
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
  def handle_event("toggle_fyi", _, socket) do
    {:noreply, assign(socket, :fyi_expanded, !socket.assigns.fyi_expanded)}
  end

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
      {:noreply, select_custom_image_ref(socket, ref)}
    end
  end

  @impl true
  def handle_event("select_pulled_chip", %{"ref" => ref}, socket) do
    {:noreply, select_custom_image_ref(socket, ref)}
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
      socket.assigns.live_action != :oss_agents ->
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
    if socket.assigns.live_action == :oss_agents do
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
  def handle_event("pull_byoi_image", _params, socket) do
    ref = socket.assigns.selected_image |> to_string() |> String.trim()

    cond do
      ref == "" ->
        {:noreply, put_flash(socket, :error, "Paste an image reference before pulling.")}

      socket.assigns.image_pull_busy ->
        {:noreply, put_flash(socket, :error, "A pull is already in progress.")}

      true ->
        pid = self()

        Task.start(fn ->
          result = Companion.Docker.impl().image_pull(ref)
          send(pid, {:image_pull_done, ref, result})
        end)

        {:noreply, assign(socket, :image_pull_busy, true)}
    end
  end

  @impl true
  def handle_event("pull_closed_agent_image", %{"service" => service}, socket) do
    entry = ClosedAgentsCatalog.by_compose_service(to_string(service))

    cond do
      is_nil(entry) ->
        {:noreply, put_flash(socket, :error, "Unknown closed-agent service.")}

      socket.assigns.image_pull_busy ->
        {:noreply, put_flash(socket, :error, "A pull is already in progress.")}

      true ->
        ref = ClosedAgentsCatalog.ghcr_main_ref(entry)
        pid = self()

        Task.start(fn ->
          result = Companion.Docker.impl().image_pull(ref)
          send(pid, {:image_pull_done, ref, result})
        end)

        {:noreply, assign(socket, :image_pull_busy, true)}
    end
  end

  @impl true
  def handle_event("set_closed_agents_tab", %{"tab" => tab}, socket) do
    tab = to_string(tab)

    if tab in Enum.map(ClosedAgentsCatalog.entries(), & &1.tab_key) do
      {:noreply, assign(socket, :closed_agents_tab, tab)}
    else
      {:noreply, socket}
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
      socket.assigns.live_action != :oss_agents ->
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
      socket.assigns.live_action != :oss_agents ->
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

  # --- Events: retardeel verifier ---

  @impl true
  def handle_event("morayeel_run", _params, socket) do
    MorayeelRunner.run()
    {:noreply, assign(socket, :morayeel, MorayeelRunner.snapshot())}
  end

  def handle_event("verify_retardeel", _params, socket) do
    cond do
      socket.assigns.live_action != :oss_agents ->
        {:noreply, socket}

      socket.assigns.retardeel_verify_status == :running ->
        {:noreply, put_flash(socket, :info, "Verification already running.")}

      true ->
        Companion.RetardeelVerifier.verify()

        {:noreply,
         socket
         |> assign(:retardeel_verify_status, :running)
         |> assign(:retardeel_verify_results, nil)}
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

  @impl true
  def handle_event("verify_closed_agent", %{"service" => service, "container-id" => cid}, socket) do
    cid = String.trim(to_string(cid || ""))

    cond do
      cid == "" ->
        {:noreply, put_flash(socket, :error, "Start the closed-agent Compose service first.")}

      is_nil(ClosedAgentsCatalog.by_compose_service(service)) ->
        {:noreply, put_flash(socket, :error, "Unknown closed-agent service.")}

      true ->
        entry = ClosedAgentsCatalog.by_compose_service(service)
        parent = self()

        Task.start(fn ->
          result =
            Companion.ClosedAgents.Verify.run(
              cid,
              entry.proxy_port,
              entry.vendor_url
            )

          send(parent, {:closed_agent_verify_done, service, cid, result})
        end)

        {:noreply,
         socket
         |> assign(:other_agents_verify_busy, true)
         |> assign(:other_agents_verify_service, service)
         |> assign(:other_agents_verify_error, nil)}
    end
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

  defp select_custom_image_ref(socket, ref) do
    ref = ref |> to_string() |> String.trim()

    socket
    |> assign(:selected_image, ref)
    |> assign(:selected_use_image_cmd, true)
    |> assign(:selected_container_cmd, nil)
    |> assign(:selected_catalog_id, nil)
    |> assign(:selected_catalog_entry, nil)
    |> assign(:selected_telvm_certified, false)
  end

  defp trimmed_chip_label(ref) when is_binary(ref) do
    ref = String.trim(ref)

    if String.length(ref) <= 44 do
      ref
    else
      String.slice(ref, 0, 41) <> "…"
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

      :oss_agents ->
        oss_agents(assigns)

      :morayeel ->
        morayeel(assigns)

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

  # --- OSS Agents tab (Ollama / Goose / Model / retardeel) ---

  defp oss_agents(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell px-3 py-3 sm:px-4 sm:py-4">
      <.terminal_nav active={@live_action} />
      <div class="flex flex-wrap items-end justify-between gap-2 telvm-accent-border-b border-b pb-2 mb-4">
        <div class="text-[11px] sm:text-xs uppercase tracking-[0.2em] telvm-accent-text font-semibold">
          telvm · oss agents
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
                <span class="telvm-accent-dim-text text-[10px] uppercase mr-1">container</span> {goose_panel_container_display(
                  @goose_container_id
                )}
              </p>
              
              <p>
                <span class="telvm-accent-dim-text text-[10px] uppercase mr-1">state</span> {@goose_status ||
                  "—"}
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
            </code> <pre
              :if={!@goose_logs_loading && !@goose_logs_error}
              class="max-h-48 overflow-y-auto rounded border p-2 text-[10px] font-mono whitespace-pre-wrap break-words"
              style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-input-bg) 92%, black); color: var(--telvm-shell-fg);"
            >{@goose_logs_text || ""}</pre>
          </aside>
          
          <aside
            class="min-w-0 rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4"
            id="agent-retardeel-panel"
          >
            <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.18em] mb-2 font-semibold">
              retardeel · filesystem agent verifier
            </div>
            
            <p class="text-[10px] mb-3" style="color: var(--telvm-shell-muted);">
              Builds the retardeel Zig binary via Docker, injects it into the sandbox container
              (<span class="font-mono telvm-accent-dim-text">telvm.sandbox=true</span>),
              and runs endpoint checks: health, workspace, stat, read, write, list, jail escape, auth.
            </p>
            
            <div class="flex flex-wrap gap-2 mb-3">
              <button
                type="button"
                phx-click="verify_retardeel"
                phx-disable-with="verifying…"
                disabled={@retardeel_verify_status == :running}
                class={[
                  "px-3 py-2 text-[10px] sm:text-xs font-mono font-semibold rounded-md border uppercase tracking-wide",
                  @retardeel_verify_status == :running &&
                    "cursor-not-allowed opacity-60 border-zinc-700",
                  @retardeel_verify_status != :running && "telvm-btn-primary"
                ]}
              >
                {if @retardeel_verify_status == :running, do: "Verifying…", else: "Verify retardeel"}
              </button>
            </div>
            
            <div
              :if={@retardeel_verify_status == :running && @retardeel_verify_results == nil}
              class="text-[10px] font-mono telvm-accent-dim-text animate-pulse"
            >
              Building image, injecting binary, running checks…
            </div>
            
            <div :if={is_list(@retardeel_verify_results)} class="space-y-1">
              <div
                :for={{name, status, detail} <- @retardeel_verify_results}
                class="flex items-baseline gap-2 text-[10px] font-mono"
              >
                <span class={retardeel_status_class(status)}>{retardeel_status_tag(status)}</span>
                <span style="color: var(--telvm-shell-fg);">{name}</span>
                <span
                  class="truncate max-w-[14rem]"
                  style="color: var(--telvm-shell-muted);"
                  title={detail}
                >
                  {detail}
                </span>
              </div>
              
              <div
                class="mt-2 pt-2 border-t text-[10px] font-mono"
                style="border-color: var(--telvm-shell-border);"
              >
                <span class="telvm-text-ok">
                  {Enum.count(@retardeel_verify_results, fn {_, s, _} -> s == :pass end)} PASS
                </span> <span class="mx-1" style="color: var(--telvm-shell-muted);">·</span>
                <span class="telvm-text-danger-ink">
                  {Enum.count(@retardeel_verify_results, fn {_, s, _} -> s == :fail end)} FAIL
                </span> <span class="mx-1" style="color: var(--telvm-shell-muted);">·</span>
                <span style="color: var(--telvm-shell-muted);">
                  {Enum.count(@retardeel_verify_results, fn {_, s, _} -> s == :skip end)} SKIP
                </span>
              </div>
            </div>
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
                    <span class="telvm-accent-dim-text text-[10px] uppercase mr-1">model</span> {@agent_chat_model}
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
    "Goose health: land here with the stack running; probes run periodically and when you open OSS Agents."
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

  defp retardeel_status_tag(:pass), do: "PASS"
  defp retardeel_status_tag(:fail), do: "FAIL"
  defp retardeel_status_tag(:skip), do: "SKIP"
  defp retardeel_status_tag(_), do: "—"

  defp retardeel_status_class(:pass), do: "telvm-text-ok font-semibold w-8"
  defp retardeel_status_class(:fail), do: "telvm-text-danger-ink font-semibold w-8"
  defp retardeel_status_class(:skip), do: "w-8"
  defp retardeel_status_class(_), do: "w-8"

  defp trim_chat_messages(msgs, max) when is_list(msgs) and max > 0 do
    if length(msgs) <= max, do: msgs, else: Enum.take(msgs, -max)
  end

  # --- Machines: vendor CLI agents (Claude / Codex) — pull, basic soak, warm ---

  defp closed_agents_machines_section(assigns) do
    ~H"""
    <section
      class="mb-5 rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4"
      id="closed-agents-machines-section"
    >
      <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.18em] mb-2 font-semibold">
        vendor CLI agents
      </div>
      
      <p class="text-[10px] mb-3 leading-snug max-w-2xl" style="color: var(--telvm-shell-muted);">
        Pull the published image, start the matching Compose service, then run
        <span class="telvm-accent-dim-text">Basic soak</span>
        (egress proxy + apt). On success the container is listed on <span class="telvm-accent-dim-text">Warm assets</span>. Promotion is in-memory until companion restarts.
        Discovery uses Compose project <span class="font-mono">{compose_project_name()}</span>
        (<code class="text-[9px]">TELVM_COMPOSE_PROJECT</code> to override).
      </p>
      
      <div
        class="flex rounded overflow-hidden text-[10px] mb-3 w-fit"
        style="border: 1px solid var(--telvm-shell-border);"
      >
        <button
          type="button"
          phx-click="set_closed_agents_tab"
          phx-value-tab="claude"
          class={[
            "px-2 py-1",
            @closed_agents_tab == "claude" && "telvm-nav-tab-active",
            @closed_agents_tab != "claude" && "telvm-nav-tab-idle"
          ]}
        >
          Node + Claude Code
        </button>
        <button
          type="button"
          phx-click="set_closed_agents_tab"
          phx-value-tab="codex"
          class={[
            "px-2 py-1 border-l",
            @closed_agents_tab == "codex" && "telvm-nav-tab-active",
            @closed_agents_tab != "codex" && "telvm-nav-tab-idle"
          ]}
          style="border-left-color: var(--telvm-shell-border);"
        >
          Node + Codex
        </button>
      </div>
      
      <div
        :if={@other_agents_verify_error}
        class="mb-3 text-[11px] font-mono telvm-text-danger-ink whitespace-pre-wrap"
        id="closed-agents-verify-error"
      >
        {@other_agents_verify_error}
      </div>
      
      <div :for={row <- @other_agents_rows} :if={row.entry.tab_key == @closed_agents_tab}>
        <div class="rounded border p-3 max-w-3xl" style="border-color: var(--telvm-shell-border);">
          <div class="text-sm font-semibold mb-1" style="color: var(--telvm-shell-fg);">
            {row.entry.card_title}
          </div>
          
          <p class="text-[10px] font-mono mb-2 telvm-accent-dim-text">{row.entry.stack_line}</p>
          
          <div
            class="rounded border p-2 mb-3 font-mono text-[10px] leading-relaxed whitespace-pre-wrap overflow-x-auto"
            style="border-color: color-mix(in oklch, var(--telvm-shell-border) 85%, transparent); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
          >
            {row.entry.stack_disclosure}
          </div>
          
          <div class="text-[10px] font-mono mb-2 break-all" style="color: var(--telvm-shell-muted);">
            <span class="telvm-accent-dim-text">image</span> {ClosedAgentsCatalog.ghcr_main_ref(
              row.entry
            )}
          </div>
          
          <div class="flex flex-wrap gap-2 mb-3">
            <button
              type="button"
              phx-click="pull_closed_agent_image"
              phx-value-service={row.entry.compose_service}
              disabled={@image_pull_busy or @vm_preflight_busy}
              class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-pull-btn disabled:opacity-40"
            >
              {if @image_pull_busy, do: "…", else: "pull image"}
            </button>
          </div>
          
          <div class="flex flex-wrap items-center gap-2 mb-2 text-[10px] font-mono">
            <span class={if(row.running, do: "telvm-text-ok", else: "telvm-text-warn")}>
              {if row.running, do: "running", else: "not running"}
            </span> <span :if={row.in_warm_registry} class="telvm-text-ok">on warm assets</span>
            <span class="telvm-accent-dim-text">
              compose · {row.entry.compose_service} · proxy companion:{row.entry.proxy_port}
            </span>
          </div>
          
          <div
            :if={row.egress_workload}
            class="text-[10px] font-mono mb-2 break-all leading-snug"
            style="color: var(--telvm-shell-muted);"
          >
            <span class="telvm-accent-dim-text">egress workload</span> {row.egress_workload.id}
            <span> · </span>
            <span class="telvm-accent-dim-text">allowlist</span> {row.egress_workload.allow_digest}
          </div>
          
          <div
            :if={!row.egress_workload && @egress_proxy_snapshot.enabled}
            class="text-[10px] font-mono mb-2 telvm-text-warn"
            style="color: var(--telvm-shell-muted);"
          >
            no egress workload in companion config for companion:{row.entry.proxy_port} — check <code class="telvm-accent-dim-text">TELVM_EGRESS_WORKLOADS</code>.
          </div>
          
          <div
            :if={
              !row.egress_workload && !@egress_proxy_snapshot.enabled &&
                @egress_proxy_snapshot.workloads != []
            }
            class="text-[10px] font-mono mb-2"
            style="color: var(--telvm-shell-muted);"
          >
            <span class="telvm-accent-dim-text">egress workloads configured but proxy disabled</span>
            — enable <code class="telvm-accent-dim-text">TELVM_EGRESS_ENABLED=1</code>
            (<.link patch={~p"/health"} class="underline telvm-accent-dim-text">Pre-flight</.link>).
          </div>
          
          <div class="text-[10px] font-mono mb-2" style="color: var(--telvm-shell-muted);">
            <span :if={row.container_id}>id {String.slice(row.container_id, 0, 12)}…</span>
            <span :if={!row.container_id}>
              no container for this service in Compose project {compose_project_name()}
            </span>
          </div>
          
          <button
            type="button"
            phx-click="verify_closed_agent"
            phx-value-service={row.entry.compose_service}
            phx-value-container-id={row.container_id || ""}
            disabled={not row.running or @other_agents_verify_busy}
            class="px-2 py-0.5 text-[10px] rounded-sm border uppercase tracking-wide telvm-btn-primary disabled:opacity-40"
          >
            {if @other_agents_verify_busy &&
                  @other_agents_verify_service == row.entry.compose_service,
                do: "soaking…",
                else: "Basic soak"}
          </button>
        </div>
      </div>
    </section>
    """
  end

  # --- Morayeel (headless Playwright lab) ---

  defp morayeel(assigns) do
    rid = assigns.morayeel[:run_id] || assigns.morayeel[:last_run_id]

    assigns = assign(assigns, :morayeel_artifact_rid, rid)

    ~H"""
    <div class="telvm-terminal telvm-console-shell px-3 py-3 sm:px-4 sm:py-4" id="morayeel-panel">
      <.terminal_nav active={@live_action} />
      <div class="flex flex-wrap items-end justify-between gap-2 telvm-accent-border-b border-b pb-2 mb-4">
        <div class="text-[11px] sm:text-xs uppercase tracking-[0.2em] telvm-accent-text font-semibold">
          telvm · morayeel
        </div>
      </div>
      
      <p
        class="telvm-prose-bar text-[11px] mb-5 font-mono leading-relaxed max-w-2xl border-l-2 pl-2"
        style="color: var(--telvm-shell-muted);"
      >
        Headless Chromium (Playwright) runs inside Docker on <span class="telvm-accent-dim-text font-mono">telvm_default</span>.
        The container sets
        <span class="telvm-accent-dim-text font-mono">HTTP_PROXY=http://companion:4003</span>
        (egress workload <span class="telvm-accent-dim-text">morayeel</span>, allowlist <span class="font-mono telvm-accent-dim-text">morayeel_lab</span>) while
        <span class="font-mono telvm-accent-dim-text">NO_PROXY</span>
        includes <span class="font-mono telvm-accent-dim-text">morayeel_lab</span>
        so the first-party lab is reached <span class="telvm-accent-dim-text">directly</span>
        on the compose network (Chromium reliably persists
        <span class="font-mono telvm-accent-dim-text">Set-Cookie</span>
        into <span class="font-mono telvm-accent-dim-text">storageState.json</span>). Writes <span class="font-mono telvm-accent-dim-text">storageState.json</span>, <span class="font-mono telvm-accent-dim-text">network.har</span>, and
        <span class="font-mono telvm-accent-dim-text">run.json</span>
        on the shared volume under <span class="font-mono telvm-accent-dim-text">morayeel_runs/</span>
        (one directory per run id).
        See <span class="font-mono telvm-accent-dim-text">docs/morayeel-verification.md</span>.
        Artifacts always include <span class="font-mono telvm-accent-dim-text">storageState.json</span>, <span class="font-mono telvm-accent-dim-text">network.har</span>, and <span class="font-mono telvm-accent-dim-text">run.json</span>; the HAR is complete after the run finishes
        (<span class="font-mono telvm-accent-dim-text">context.close()</span> in Playwright).
      </p>
      
      <section class="rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4 mb-4 space-y-3">
        <h2 class="text-[11px] sm:text-xs uppercase tracking-[0.15em] font-semibold telvm-accent-text mb-2">
          Operator runbook
        </h2>
        
        <p
          class="text-[11px] font-mono leading-relaxed telvm-muted-xs mb-3"
          style="color: var(--telvm-shell-muted);"
        >
          The button below runs <span class="telvm-accent-dim-text">headless</span>
          Playwright <span class="telvm-accent-dim-text">inside Docker</span>
          only.
          Headed runs happen on your laptop using the same <span class="font-mono telvm-accent-dim-text">run.mjs</span>; this section is the copy-paste guide.
        </p>
        
        <details class="group mb-2 rounded-sm border telvm-panel-border telvm-panel-bg open:pb-2">
          <summary class="cursor-pointer select-none px-2 py-1.5 text-[11px] font-mono telvm-accent-dim-text hover:opacity-90">
            Container vs local (what differs)
          </summary>
          
          <div class="px-2 pb-2 overflow-x-auto">
            <table
              class="w-full text-left text-[10px] font-mono border-collapse mt-1"
              style="color: var(--telvm-shell-muted);"
            >
              <thead>
                <tr class="border-b" style="border-color: var(--telvm-shell-border);">
                  <th class="py-1 pr-2 font-semibold telvm-accent-dim-text">Aspect</th>
                  
                  <th class="py-1 pr-2 font-semibold telvm-accent-dim-text">In Docker (default)</th>
                  
                  <th class="py-1 font-semibold telvm-accent-dim-text">On your machine</th>
                </tr>
              </thead>
              
              <tbody>
                <tr
                  :for={row <- @morayeel_operator_guide.comparison_rows}
                  class="border-b align-top"
                  style="border-color: var(--telvm-shell-border);"
                >
                  <td class="py-1.5 pr-2 font-semibold text-[var(--telvm-shell-fg)]">{row.topic}</td>
                  
                  <td class="py-1.5 pr-2">{row.in_docker}</td>
                  
                  <td class="py-1.5">{row.locally}</td>
                </tr>
              </tbody>
            </table>
          </div>
        </details>
        
        <details class="group mb-2 rounded-sm border telvm-panel-border telvm-panel-bg open:pb-2">
          <summary class="cursor-pointer select-none px-2 py-1.5 text-[11px] font-mono telvm-accent-dim-text hover:opacity-90">
            Path 1 — Headless in Docker (same as LiveView button)
          </summary>
          
          <div class="px-2 pb-2 space-y-2">
            <pre
              class="p-2 text-[10px] font-mono rounded-sm overflow-x-auto whitespace-pre"
              style="border: 1px solid var(--telvm-shell-border); background: var(--telvm-input-bg);"
            >{@morayeel_operator_guide.docker_smoke_snippet}</pre>
            <p class="text-[10px] font-mono telvm-muted-xs">
              {@morayeel_operator_guide.docker_session_hint}
            </p>
          </div>
        </details>
        
        <details class="group mb-2 rounded-sm border telvm-panel-border telvm-panel-bg open:pb-2">
          <summary class="cursor-pointer select-none px-2 py-1.5 text-[11px] font-mono telvm-accent-dim-text hover:opacity-90">
            Path 2 — Install Playwright (local; all OS)
          </summary>
          
          <div class="px-2 pb-2 space-y-3">
            <p class="text-[10px] font-mono telvm-muted-xs">
              Install
              <a
                href={@morayeel_operator_guide.playwright_intro_url}
                class="underline telvm-accent-dim-text"
                target="_blank"
                rel="noopener noreferrer"
              >
                Playwright system dependencies
              </a>
              from upstream when browsers fail to launch.
            </p>
            
            <div :for={block <- @morayeel_operator_guide.install_os_blocks} class="space-y-1">
              <div class="text-[10px] font-semibold telvm-accent-dim-text">{block.os}</div>
               <pre
                class="p-2 text-[10px] font-mono rounded-sm overflow-x-auto whitespace-pre"
                style="border: 1px solid var(--telvm-shell-border); background: var(--telvm-input-bg);"
              >{Enum.join(block.lines, "\n")}</pre>
            </div>
          </div>
        </details>
        
        <details class="group mb-2 rounded-sm border telvm-panel-border telvm-panel-bg open:pb-2">
          <summary class="cursor-pointer select-none px-2 py-1.5 text-[11px] font-mono telvm-accent-dim-text hover:opacity-90">
            Path 2 — Run locally (headless vs headed)
          </summary>
          
          <div class="px-2 pb-2 space-y-2">
            <div class="text-[10px] font-semibold telvm-accent-dim-text">Headless</div>
             <pre
              class="p-2 text-[10px] font-mono rounded-sm overflow-x-auto whitespace-pre"
              style="border: 1px solid var(--telvm-shell-border); background: var(--telvm-input-bg);"
            >{@morayeel_operator_guide.local_headless_snippet}</pre>
            <div class="text-[10px] font-semibold telvm-accent-dim-text">Headed (visible window)</div>
             <pre
              class="p-2 text-[10px] font-mono rounded-sm overflow-x-auto whitespace-pre"
              style="border: 1px solid var(--telvm-shell-border); background: var(--telvm-input-bg);"
            >{@morayeel_operator_guide.local_headed_snippet}</pre>
            <p class="text-[10px] font-mono telvm-muted-xs">
              Or set <span class="font-mono">MORAYEEL_HEADLESS=0</span>
              and run <span class="font-mono">node run.mjs</span>.
              Full env reference: <span class="font-mono">{@morayeel_operator_guide.readme_path}</span>.
            </p>
          </div>
        </details>
        
        <details class="group rounded-sm border telvm-panel-border telvm-panel-bg open:pb-2">
          <summary class="cursor-pointer select-none px-2 py-1.5 text-[11px] font-mono telvm-accent-dim-text hover:opacity-90">
            When to use headed vs session (CDP)
          </summary>
          
          <div
            class="px-2 pb-2 space-y-2 text-[10px] font-mono leading-relaxed telvm-muted-xs"
            style="color: var(--telvm-shell-muted);"
          >
            <p>{@morayeel_operator_guide.when_to_use}</p>
            
            <p>
              Repo docs: <span class="font-mono telvm-accent-dim-text">{@morayeel_operator_guide.additions_doc}</span>, <span class="font-mono telvm-accent-dim-text">{@morayeel_operator_guide.verification_doc}</span>.
            </p>
          </div>
        </details>
      </section>
      
      <section class="rounded-sm telvm-panel-border border telvm-panel-bg p-3 sm:p-4 mb-4 space-y-3">
        <div class="flex flex-wrap items-center gap-2">
          <span class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] font-semibold">
            status
          </span> <span class="font-mono text-xs">{inspect(@morayeel.status)}</span>
          <span :if={@morayeel[:run_id]} class="telvm-muted-xs font-mono">
            run {@morayeel[:run_id]}
          </span>
          <span :if={@morayeel[:exit_code] != nil} class="telvm-muted-xs font-mono">
            exit {@morayeel[:exit_code]}
          </span>
        </div>
        
        <div class="flex flex-wrap gap-2">
          <button
            type="button"
            phx-click="morayeel_run"
            disabled={@morayeel.status == :running}
            class={[
              "px-3 py-1 text-[11px] font-mono border rounded-sm",
              @morayeel.status == :running && "opacity-50 cursor-not-allowed",
              @morayeel.status != :running && "telvm-btn-primary"
            ]}
          >
            {if @morayeel.status == :running, do: "Running…", else: "Run headless lab"}
          </button>
        </div>
        
        <div :if={is_map(@morayeel[:summary])} class="text-[11px] font-mono space-y-1 telvm-muted-xs">
          <div>
            cookies: {Map.get(@morayeel[:summary], :cookie_count, 0)} — {Enum.join(
              Map.get(@morayeel[:summary], :cookie_names, []),
              ", "
            )}
          </div>
          
          <div :if={Map.get(@morayeel[:summary], :origins, []) != []}>
            domains: {Enum.join(Map.get(@morayeel[:summary], :origins, []), ", ")}
          </div>
        </div>
        
        <div :if={@morayeel_artifact_rid} class="flex flex-wrap gap-x-3 gap-y-1 text-[11px] font-mono">
          <a
            class="underline telvm-accent-dim-text"
            href={~p"/telvm/morayeel/artifacts/#{@morayeel_artifact_rid}/storageState.json"}
          >
            storageState.json
          </a>
          <a
            class="underline telvm-accent-dim-text"
            href={~p"/telvm/morayeel/artifacts/#{@morayeel_artifact_rid}/network.har"}
          >
            network.har
          </a>
          <a
            class="underline telvm-accent-dim-text"
            href={~p"/telvm/morayeel/artifacts/#{@morayeel_artifact_rid}/run.json"}
          >
            run.json
          </a>
          <a
            class="underline telvm-accent-dim-text"
            href={~p"/telvm/morayeel/artifacts/#{@morayeel_artifact_rid}/runner.log"}
          >
            runner.log
          </a>
        </div>
        
        <div :if={@morayeel[:docker_log] != "" && @morayeel[:docker_log]} class="space-y-1">
          <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] font-semibold">
            docker log (tail)
          </div>
           <pre
            class="h-48 overflow-auto p-2 text-[10px] font-mono rounded-sm whitespace-pre-wrap break-all"
            style="border: 1px solid var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-muted);"
          >{@morayeel[:docker_log]}</pre>
        </div>
      </section>
    </div>
    """
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
          Port preview or Monaco (files). Labs: verify on Machines. Closed agents listed here passed
          <span class="telvm-accent-dim-text">Basic soak</span>
          (CONNECT via companion egress + <span class="telvm-accent-dim-text">apt-get update</span>); vendor HTTPS is allow-listed per workload on companion (
          <.link patch={~p"/health"} class="underline telvm-accent-dim-text">Pre-flight</.link>
          ). Pull + soak from Vendor CLI agents on Machines.
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
          Live snapshot: Compose stack + warm rows (labs and verified closed agents). Refreshes with the warm list.
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
        No warm rows — verify a lab on Machines, or run Basic soak for a vendor CLI agent under Machines (Compose must be running).
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
              <span
                :if={Map.get(m, :kind, :lab) != :closed_agent}
                class={live_activity_class(m, @soak_session, @preflight_session)}
              >
                {live_activity_txt(m, @soak_session, @preflight_session)}
              </span>
              <span
                :if={Map.get(m, :kind, :lab) != :closed_agent}
                class={soak_badge_class(@lab_readiness[m.id])}
              >
                {soak_badge_txt(@lab_readiness[m.id])}
              </span>
              <span
                :if={Map.get(m, :kind, :lab) != :closed_agent}
                class={port_probe_class(@lab_readiness[m.id], m.ports)}
              >
                {port_probe_txt(@lab_readiness[m.id], m.ports)}
              </span>
              <span class={["font-medium text-[10px]", warm_status_class(m.status)]}>
                <%= if Map.get(m, :kind, :lab) == :closed_agent do %>
                  {m.status}
                <% else %>
                  {String.slice(m.status, 0, 4)}
                <% end %>
              </span>
              <div
                :if={Map.get(m, :kind, :lab) != :closed_agent && warm_machine_running?(m)}
                class="flex flex-wrap items-center gap-1"
              >
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
              
              <div
                :if={Map.get(m, :kind, :lab) != :closed_agent && warm_machine_paused?(m)}
                class="flex flex-wrap items-center gap-1"
              >
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
              
              <div
                :if={Map.get(m, :kind, :lab) != :closed_agent && warm_machine_destroy_only?(m)}
                class="flex flex-wrap items-center gap-1"
              >
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
            
            <div class="flex flex-col gap-2">
              <div
                :if={Map.get(m, :kind, :lab) == :closed_agent && Map.get(m, :egress_internal_url)}
                class="flex flex-col gap-1.5"
              >
                <div class="text-[10px] uppercase tracking-[0.12em] font-semibold telvm-accent-dim-text">
                  Egress
                </div>
                
                <div
                  :if={Map.get(m, :egress_workload_id)}
                  class="text-[10px] font-mono space-y-1"
                  style="color: var(--telvm-shell-fg);"
                >
                  <div class="break-all">
                    <span class="telvm-accent-dim-text">workload</span> {Map.get(
                      m,
                      :egress_workload_id
                    )} <span style="color: var(--telvm-shell-muted);"> · </span>
                    <span class="telvm-accent-dim-text">listener</span> {Map.get(
                      m,
                      :egress_internal_url
                    )}
                  </div>
                  
                  <div :if={Map.get(m, :egress_allow_digest)} class="break-all">
                    <span class="telvm-accent-dim-text">allowlist</span> {Map.get(
                      m,
                      :egress_allow_digest
                    )}
                  </div>
                  
                  <p class="text-[9px] leading-snug" style="color: var(--telvm-shell-muted);">
                    <code class="telvm-accent-dim-text">HTTP(S)_PROXY</code>
                    points here; HTTPS is <code class="telvm-accent-dim-text">CONNECT</code>
                    + allowlist in companion (
                    <.link patch={~p"/health"} class="underline telvm-accent-dim-text">
                      Pre-flight
                    </.link>
                    for denies).
                  </p>
                  
                  <div
                    :if={Map.get(m, :compose_service) && Map.get(m, :vendor_url)}
                    class="space-y-0.5"
                  >
                    <div class="text-[9px] uppercase tracking-wide telvm-accent-dim-text">
                      Re-verify (repo root, Compose up)
                    </div>
                     <pre
                      class="text-[9px] font-mono leading-snug p-2 rounded border overflow-x-auto select-all whitespace-pre-wrap"
                      style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                      title="Expect proxy_ok on stdout; docker exit code 0 means the probe succeeded."
                    >{warm_closed_proxy_probe_command(m)}</pre>
                    <p class="text-[9px] leading-snug" style="color: var(--telvm-shell-muted);">
                      <code class="telvm-accent-dim-text">curl -sS -o /dev/null</code>
                      prints nothing by design; this command then prints
                      <code class="telvm-accent-dim-text">proxy_ok</code>
                      or <code class="telvm-accent-dim-text">proxy_fail</code>
                      . Same HTTPS path as Basic soak. PowerShell: you can also run
                      <code class="telvm-accent-dim-text">echo $LASTEXITCODE</code>
                      after any compose exec (expect <code class="telvm-accent-dim-text">0</code>
                      ). CONNECT-only: <code class="telvm-accent-dim-text">dirteel egress-probe</code>
                      with the same proxy and vendor URL when dirteel is installed.
                    </p>
                  </div>
                </div>
                
                <div
                  :if={
                    Map.get(m, :kind, :lab) == :closed_agent && Map.get(m, :egress_internal_url) &&
                      !Map.get(m, :egress_workload_id) && @egress_proxy_snapshot.enabled
                  }
                  class="text-[10px] font-mono telvm-accent-dim-text break-all"
                >
                  listener {Map.get(m, :egress_internal_url)}
                  <span
                    class="block text-[9px] mt-1 telvm-text-warn"
                    style="color: var(--telvm-shell-muted);"
                  >
                    no matching egress workload for this port in companion config.
                  </span>
                </div>
                
                <div
                  :if={
                    Map.get(m, :kind, :lab) == :closed_agent && !@egress_proxy_snapshot.enabled &&
                      @egress_proxy_snapshot.workloads != []
                  }
                  class="text-[10px] font-mono"
                  style="color: var(--telvm-shell-muted);"
                >
                  <span class="telvm-accent-dim-text">egress proxy configured but disabled</span>
                  — set <code class="telvm-accent-dim-text">TELVM_EGRESS_ENABLED=1</code>
                  and restart companion (
                  <.link patch={~p"/health"} class="underline telvm-accent-dim-text">
                    Pre-flight
                  </.link>
                  ).
                </div>
                
                <div
                  :if={
                    Map.get(m, :kind, :lab) == :closed_agent && !@egress_proxy_snapshot.enabled &&
                      @egress_proxy_snapshot.workloads == []
                  }
                  class="text-[10px] font-mono telvm-accent-dim-text break-all"
                >
                  egress {Map.get(m, :egress_internal_url)}
                  <span class="block text-[9px] mt-1" style="color: var(--telvm-shell-muted);">
                    companion egress workloads not loaded — see Pre-flight.
                  </span>
                </div>
              </div>
              
              <div class="flex flex-wrap items-center gap-2">
                <span
                  :if={
                    Map.get(m, :kind, :lab) != :closed_agent && m.ports == [] and
                      m.internal_ports == []
                  }
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
          <div class="flex gap-2 items-stretch">
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
              class="min-w-0 flex-1 px-2 py-2 text-xs font-mono border rounded-md telvm-accent-ring disabled:opacity-50 placeholder:opacity-60"
              style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
            />
            <button
              type="button"
              id="byoi-pull-btn"
              phx-click="pull_byoi_image"
              disabled={@image_pull_busy or @vm_preflight_busy or String.trim(@selected_image) == ""}
              title={"Pull #{String.trim(@selected_image)}"}
              class="shrink-0 px-3 py-2 text-[10px] uppercase tracking-wide rounded-md border telvm-pull-btn disabled:opacity-40"
            >
              {if @image_pull_busy, do: "…", else: "pull"}
            </button>
          </div>
          
          <p class="text-[10px] mt-1.5" style="color: var(--telvm-shell-muted);">
            Pick a chip or paste any Docker reference. Custom CMD may be required for verify to pass.
          </p>
        </div>
        
        <div :if={@saved_pull_refs != []} class="mt-4 max-w-4xl" id="saved-pull-chips">
          <div class="telvm-accent-dim-text text-[10px] uppercase tracking-[0.12em] mb-2 font-semibold">
            pulled for verify / soak
          </div>
          
          <p class="text-[10px] mb-2 leading-snug" style="color: var(--telvm-shell-muted);">
            Select a ref to load it into the field above, then run lab verification (same as BYOI).
          </p>
          
          <div class="flex flex-wrap gap-2">
            <button
              :for={ref <- @saved_pull_refs}
              type="button"
              phx-click="select_pulled_chip"
              phx-value-ref={ref}
              title={ref}
              class={[
                "max-w-[220px] truncate rounded-md border px-2.5 py-1.5 text-left text-[10px] font-mono transition-colors",
                "telvm-pull-btn hover:opacity-95",
                @selected_image == ref && is_nil(@selected_catalog_id) &&
                  "ring-2 ring-[color-mix(in_oklch,var(--telvm-accent)_45%,transparent)] border-[color-mix(in_oklch,var(--telvm-accent)_35%,transparent)]"
              ]}
            >
              {trimmed_chip_label(ref)}
            </button>
          </div>
        </div>
      </section>
       {closed_agents_machines_section(assigns)} <%!-- Lab verification card --%>
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
      
      <div class="flex flex-wrap gap-3 mb-5">
        <div class="telvm-panel-border border rounded p-3 space-y-2" style="width: 300px;">
          <div class="flex items-baseline gap-2">
            <span class="text-xs font-semibold" style="color: var(--telvm-shell-fg);">
              telvm companion
            </span>
            <span class="text-[10px] font-mono" style="color: var(--telvm-shell-muted);">Docker</span>
          </div>
          
          <div class="grid grid-cols-2 gap-x-3 gap-y-1 text-[11px] font-mono">
            <span style="color: var(--telvm-shell-muted);">status</span>
            <span class="telvm-text-ok">running</span>
            <span style="color: var(--telvm-shell-muted);">engine</span>
            <span style="color: var(--telvm-shell-fg);">{engine_version_from_report(@report)}</span>
            <span style="color: var(--telvm-shell-muted);">socket</span>
            <span style="color: var(--telvm-shell-fg);">/var/run/docker.sock</span>
            <span style="color: var(--telvm-shell-muted);">API</span>
            <span class="telvm-accent-dim-text">:4000/telvm/api</span>
            <span style="color: var(--telvm-shell-muted);">MCP transport</span>
            <span style="color: var(--telvm-shell-fg);">stdio</span>
          </div>
        </div>
        
        <div class="telvm-panel-border border rounded p-3 space-y-2" style="width: 300px;">
          <div class="flex items-baseline gap-2">
            <span class="text-xs font-semibold" style="color: var(--telvm-shell-fg);">
              telvm-network-agent
            </span>
            <span class="text-[10px] font-mono" style="color: var(--telvm-shell-muted);">
              PowerShell
            </span>
          </div>
          
          <div
            :if={@network_agent_snapshot && @network_agent_snapshot.health.status == :ok}
            class="grid grid-cols-2 gap-x-3 gap-y-1 text-[11px] font-mono"
          >
            <span style="color: var(--telvm-shell-muted);">status</span>
            <span class="telvm-text-ok">ok</span>
            <span style="color: var(--telvm-shell-muted);">hostname</span>
            <span style="color: var(--telvm-shell-fg);">
              {(@network_agent_snapshot.health.data && @network_agent_snapshot.health.data["hostname"]) ||
                "?"}
            </span> <span style="color: var(--telvm-shell-muted);">version</span>
            <span style="color: var(--telvm-shell-fg);">
              {(@network_agent_snapshot.health.data && @network_agent_snapshot.health.data["version"]) ||
                "?"}
            </span> <span style="color: var(--telvm-shell-muted);">role</span>
            <span style="color: var(--telvm-shell-fg);">NAT gateway + DHCP</span>
            <span style="color: var(--telvm-shell-muted);">gateway IP</span>
            <span class="telvm-accent-dim-text">
              {@network_agent_snapshot.ics_status["gateway_ip"] || "?"}
            </span> <span style="color: var(--telvm-shell-muted);">subnet</span>
            <span class="telvm-accent-dim-text">
              {@network_agent_snapshot.ics_status["subnet"] || "?"}
            </span> <span style="color: var(--telvm-shell-muted);">uplink</span>
            <span style="color: var(--telvm-shell-fg);">
              {(@network_agent_snapshot.health.data && @network_agent_snapshot.health.data["ics"] &&
                  @network_agent_snapshot.health.data["ics"]["public_adapter"]) || "?"} {if @network_agent_snapshot.health.data &&
                                                                                              @network_agent_snapshot.health.data[
                                                                                                "uplink_reachable"
                                                                                              ],
                                                                                            do:
                                                                                              " (online)",
                                                                                            else:
                                                                                              " (offline)"}
            </span> <span style="color: var(--telvm-shell-muted);">private NIC</span>
            <span style="color: var(--telvm-shell-fg);">
              {(@network_agent_snapshot.health.data && @network_agent_snapshot.health.data["ics"] &&
                  @network_agent_snapshot.health.data["ics"]["private_adapter"]) || "?"}
            </span> <span style="color: var(--telvm-shell-muted);">API</span>
            <span class="telvm-accent-dim-text">:9225</span>
          </div>
          
          <div
            :if={is_nil(@network_agent_snapshot) || @network_agent_snapshot.health.status != :ok}
            class="text-[11px] font-mono"
            style="color: var(--telvm-shell-muted);"
          >
            <span class="telvm-text-danger-ink">unreachable</span> <span> - start with </span>
            <code class="telvm-accent-dim-text">Start-NetworkAgent.ps1</code>
          </div>
        </div>
        
        <div class="telvm-panel-border border rounded p-3 space-y-2" style="width: 320px;">
          <div class="flex items-baseline gap-2">
            <span class="text-xs font-semibold" style="color: var(--telvm-shell-fg);">
              egress proxy
            </span>
            <span class="text-[10px] font-mono" style="color: var(--telvm-shell-muted);">
              Companion / OTP
            </span>
          </div>
          
          <div
            :if={not @egress_proxy_snapshot.enabled and @egress_proxy_snapshot.workloads == []}
            class="text-[11px] font-mono"
            style="color: var(--telvm-shell-muted);"
          >
            <span class="telvm-accent-dim-text">disabled</span> <span> — set </span>
            <code class="telvm-accent-dim-text">TELVM_EGRESS_ENABLED=1</code> <span> and </span>
            <code class="telvm-accent-dim-text">TELVM_EGRESS_WORKLOADS</code>
            <span> (see .env.example).</span>
          </div>
          
          <div
            :if={not @egress_proxy_snapshot.enabled and @egress_proxy_snapshot.workloads != []}
            class="text-[11px] font-mono space-y-1"
            style="color: var(--telvm-shell-muted);"
          >
            <div>
              <span class="telvm-accent-dim-text">configured but not running</span>
              <span> — enable with </span>
              <code class="telvm-accent-dim-text">TELVM_EGRESS_ENABLED=1</code>
              <span> and restart companion.</span>
            </div>
          </div>
          
          <div class="space-y-2 text-[11px] font-mono">
            <div
              :if={@egress_proxy_snapshot.enabled}
              class="flex flex-wrap gap-x-2 gap-y-1"
              style="color: var(--telvm-shell-muted);"
            >
              <span>PubSub</span> <span class="telvm-accent-dim-text">egress_proxy:updates</span>
            </div>
            
            <p
              :if={@egress_proxy_snapshot.enabled and @egress_proxy_snapshot.workloads != []}
              class="text-[10px] leading-snug"
              style="color: var(--telvm-shell-muted);"
            >
              Other containers use <code class="telvm-accent-dim-text">http://companion:4001</code>
              / <code class="telvm-accent-dim-text">:4002</code>
              on the Compose bridge (see workload <span class="telvm-accent-dim-text">proxy</span>
              below). The host only exposes Phoenix on
              <code class="telvm-accent-dim-text">localhost:4000</code>
              ; egress listeners are inside the companion container. Canonical in-cluster check:
              <.link patch={~p"/machines"} class="underline telvm-accent-dim-text">Machines</.link>
              → Vendor CLI agents → <span class="telvm-accent-dim-text">Basic soak</span>.
            </p>
            
            <div
              :if={@egress_proxy_snapshot.workloads == []}
              style="color: var(--telvm-shell-muted);"
            >
              No workloads in config.
            </div>
            
            <div
              :for={w <- @egress_proxy_snapshot.workloads}
              class="telvm-panel-border border rounded p-2 space-y-1"
            >
              <div class="flex flex-wrap gap-x-2">
                <span style="color: var(--telvm-shell-muted);">id</span>
                <span style="color: var(--telvm-shell-fg);">{w.id}</span>
              </div>
              
              <div class="flex flex-wrap gap-x-2">
                <span style="color: var(--telvm-shell-muted);">proxy</span>
                <span class="telvm-accent-dim-text break-all">{w.internal_url}</span>
              </div>
              
              <div class="flex flex-wrap gap-x-2">
                <span style="color: var(--telvm-shell-muted);">allowlist</span>
                <span class="telvm-accent-dim-text break-all">{w.allow_digest}</span>
              </div>
              
              <div class="flex flex-wrap gap-x-2">
                <span style="color: var(--telvm-shell-muted);">auth inject</span>
                <span :if={w.inject_auth_configured} class="telvm-text-ok">configured</span>
                <span :if={not w.inject_auth_configured} style="color: var(--telvm-shell-muted);">
                  off
                </span>
              </div>
            </div>
            
            <div
              :if={@egress_proxy_snapshot.enabled and @egress_proxy_snapshot.recent_denies != []}
              class="space-y-1"
            >
              <div
                class="text-[10px] uppercase tracking-wide"
                style="color: var(--telvm-shell-muted);"
              >
                recent denies
              </div>
              
              <div
                :for={d <- Enum.take(@egress_proxy_snapshot.recent_denies, 8)}
                class="term-row text-[10px] break-all"
              >
                <span class="telvm-accent-dim-text">{d.workload_id}</span>
                <span style="color: var(--telvm-shell-muted);"> · </span> <span>{d.host}</span>
                <span style="color: var(--telvm-shell-muted);"> · </span>
                <span>{inspect(d.reason)}</span>
                <span style="color: var(--telvm-shell-muted);"> · </span>
                <span class="tabular-nums">{Calendar.strftime(d.at, "%H:%M:%S")}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
      
      <div>
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
          
          <section class="mb-5" id="lan-hosts-section">
            <div
              class="text-[11px] uppercase tracking-wide mb-1 font-semibold"
              style="color: var(--telvm-shell-muted);"
            >
              lan hosts
            </div>
            
            <p class="text-xs mb-2 leading-relaxed max-w-2xl" style="color: var(--telvm-shell-muted);">
              ICS gateway discovery via
              <span class="font-mono telvm-accent-dim-text">telvm-network-agent</span>
              + Zig agent probe on <span class="font-mono telvm-accent-dim-text">:9100/health</span>.
              PubSub <span class="font-mono telvm-accent-dim-text">network_agent:updates</span>
              · <span class="font-mono telvm-accent-dim-text">Companion.NetworkAgentPoller</span>
            </p>
            
            <div
              :if={is_nil(@network_agent_snapshot)}
              class="text-xs font-mono py-2"
              style="color: var(--telvm-shell-muted);"
            >
              Waiting for first poll from network agent...
            </div>
            
            <div :if={@network_agent_snapshot} class="space-y-2">
              <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 text-xs">
                <span style="color: var(--telvm-shell-muted);">gateway agent</span>
                <span
                  :if={@network_agent_snapshot.health.status == :ok}
                  class="font-mono telvm-text-ok"
                >
                  ok
                </span>
                <span
                  :if={@network_agent_snapshot.health.status != :ok}
                  class="font-mono telvm-text-danger-ink"
                >
                  unreachable
                </span> <span style="color: var(--telvm-shell-muted);">·</span>
                <span class="font-mono tabular-nums" style="color: var(--telvm-shell-muted);">
                  {Calendar.strftime(@network_agent_snapshot.checked_at, "%H:%M:%S")}
                </span> <span style="color: var(--telvm-shell-muted);">·</span>
                <span class="font-mono" style="color: var(--telvm-shell-muted);">
                  {@network_agent_snapshot.host_count} host(s) on wire
                </span>
              </div>
              
              <div
                :if={@network_agent_snapshot.ics_status != %{}}
                class="flex flex-wrap gap-x-4 gap-y-1 text-[11px] font-mono py-1 px-2 rounded telvm-panel-border border"
                style="color: var(--telvm-shell-muted);"
              >
                <span>
                  Gateway:
                  <span class="telvm-accent-dim-text">
                    {@network_agent_snapshot.ics_status["gateway_ip"] || "?"}
                  </span> <span style="opacity:0.5">(this PC)</span>
                </span>
                <span>
                  Subnet:
                  <span class="telvm-accent-dim-text">
                    {@network_agent_snapshot.ics_status["subnet"] || "?"}
                  </span>
                </span> <span>DHCP: <span class="telvm-accent-dim-text">ICS (Windows)</span></span>
                <span>
                  Uplink:
                  <span class="telvm-accent-dim-text">
                    {@network_agent_snapshot.ics_status["public_adapter"] || "?"}
                  </span>
                </span>
              </div>
              
              <div
                :if={@network_agent_snapshot.hosts != []}
                class="overflow-x-auto telvm-panel-border border"
              >
                <div class="grid grid-cols-12 gap-x-2 px-2 py-1 text-[10px] uppercase tracking-wide telvm-term-header">
                  <span class="col-span-2">ip</span> <span class="col-span-3">mac</span>
                  <span class="col-span-2">arp</span> <span class="col-span-2">zig agent</span>
                  <span class="col-span-3">hostname</span>
                </div>
                
                <div :for={host <- @network_agent_snapshot.hosts} class="term-row">
                  <div class="col-span-2 font-mono text-xs" style="color: var(--telvm-shell-fg);">
                    {host["ip"]}
                  </div>
                  
                  <div
                    class="col-span-3 font-mono text-xs truncate"
                    style="color: var(--telvm-shell-muted);"
                  >
                    {host["mac"]}
                  </div>
                  
                  <div class="col-span-2 text-xs">
                    <span
                      :if={host["state"] in ["Permanent", "Reachable"]}
                      class="font-mono telvm-text-ok text-[11px]"
                    >
                      {host["state"]}
                    </span>
                    <span
                      :if={host["state"] not in ["Permanent", "Reachable"]}
                      class="font-mono telvm-text-warn text-[11px]"
                    >
                      {host["state"] || "?"}
                    </span>
                  </div>
                  
                  <div class="col-span-2 text-xs">
                    <span
                      :if={host["zig_agent_status"] == "ok"}
                      class="font-mono telvm-text-ok font-bold text-[11px]"
                    >
                      ok
                    </span>
                    <span
                      :if={host["zig_agent_status"] == "unreachable"}
                      class="font-mono telvm-text-danger-ink text-[11px]"
                    >
                      no agent
                    </span>
                    <span
                      :if={host["zig_agent_status"] not in ["ok", "unreachable"]}
                      class="font-mono text-[11px]"
                      style="color: var(--telvm-shell-muted);"
                    >
                      {host["zig_agent_status"] || "?"}
                    </span>
                  </div>
                  
                  <div
                    class="col-span-3 font-mono text-xs truncate"
                    style="color: var(--telvm-shell-muted);"
                  >
                    {(host["zig_agent_health"] && host["zig_agent_health"]["hostname"]) || "-"}
                  </div>
                </div>
              </div>
              
              <div
                :if={@network_agent_snapshot.hosts == []}
                class="text-xs font-mono py-1"
                style="color: var(--telvm-shell-muted);"
              >
                No hosts discovered on ICS subnet yet. Ensure cluster machines are powered on and connected to the switch.
              </div>
            </div>
          </section>
          
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
                </span> <span style="color: var(--telvm-shell-muted);"> — </span>
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
      </div>
      
      <div class="mt-4">
        <button
          phx-click="toggle_fyi"
          class="flex items-center gap-1 text-[11px] uppercase tracking-wide cursor-pointer"
          style="color: var(--telvm-shell-muted); background: none; border: none; padding: 0;"
        >
          <span>{if @fyi_expanded, do: "▾", else: "▸"}</span> <span>api reference</span>
        </button>
        <div :if={@fyi_expanded} class="mt-2">
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

  defp fetch_warm_machines_merged do
    egress_snap = Companion.EgressProxy.snapshot()

    labs =
      fetch_warm_machines()
      |> Enum.map(&Map.put(&1, :kind, :lab))

    labs ++ fetch_warm_closed_agents(egress_snap)
  end

  defp fetch_warm_closed_agents(egress_snap) do
    verified = MapSet.new(ClosedAgentWarmRegistry.verified_ids())
    docker = Companion.Docker.impl()

    case docker.container_list(
           filters: %{
             "label" => ["telvm.agent=closed", "com.docker.compose.project=telvm"]
           }
         ) do
      {:ok, containers} ->
        containers
        |> Enum.filter(&MapSet.member?(verified, &1["Id"]))
        |> Enum.map(&closed_agent_warm_row(&1, egress_snap))

      {:error, _} ->
        []
    end
  end

  defp closed_agent_warm_row(c, egress_snap) do
    labels = c["Labels"] || %{}
    service = labels["com.docker.compose.service"] || ""

    entry =
      ClosedAgentsCatalog.by_compose_service(service) ||
        ClosedAgentsCatalog.by_product(labels["telvm.agent.product"] || "")

    base = extract_warm_info(c)
    port = if entry, do: entry.proxy_port, else: 4001
    title = if entry, do: entry.label, else: base.name

    workload =
      Enum.find(egress_snap.workloads || [], fn w ->
        match?(%{port: ^port}, w)
      end)

    vendor_url = if(entry, do: entry.vendor_url, else: nil)

    egress_attrs = %{
      egress_proxy_enabled: egress_snap.enabled,
      egress_workload_id: if(workload, do: workload.id),
      egress_allow_digest: if(workload, do: workload.allow_digest),
      vendor_url: vendor_url
    }

    Map.merge(base, %{
      kind: :closed_agent,
      name: title,
      ports: [],
      internal_ports: [],
      egress_internal_url: "http://companion:#{port}",
      egress_proxy_port: port,
      compose_service: service
    })
    |> Map.merge(egress_attrs)
  end

  defp warm_closed_proxy_probe_command(m) do
    svc = Map.get(m, :compose_service) || "SERVICE"
    port = Map.get(m, :egress_proxy_port) || 4001
    vu = Map.get(m, :vendor_url) || "https://example.invalid/"

    # sh -c so we can echo a line: bare curl -sS -o /dev/null prints nothing on success (confusing in PS).
    # Catalog vendor_url values must not contain single quotes for this quoting.
    "docker compose exec -T #{svc} sh -c 'curl -sS -o /dev/null --max-time 25 --proxy http://companion:#{port} #{vu} && echo proxy_ok || echo proxy_fail'"
  end

  defp egress_workload_for_port(egress_snap, port) when is_integer(port) do
    Enum.find(egress_snap.workloads || [], fn w ->
      match?(%{port: ^port}, w)
    end)
  end

  defp egress_workload_for_port(_, _), do: nil

  defp compose_project_name do
    case System.get_env("TELVM_COMPOSE_PROJECT") do
      nil -> "telvm"
      "" -> "telvm"
      p -> p |> String.trim()
    end
  end

  defp fetch_other_agents_rows do
    docker = Companion.Docker.impl()
    proj = compose_project_name()

    containers =
      case docker.container_list(
             filters: %{
               "label" => [
                 "telvm.agent=closed",
                 "com.docker.compose.project=#{proj}"
               ]
             }
           ) do
        {:ok, c} -> c
        _ -> []
      end

    by_service =
      for c <- containers,
          labels = c["Labels"] || %{},
          svc = labels["com.docker.compose.service"],
          is_binary(svc) and svc != "",
          into: %{} do
        {svc, c}
      end

    egress_snap = Companion.EgressProxy.snapshot()

    Enum.map(ClosedAgentsCatalog.entries(), fn entry ->
      c = Map.get(by_service, entry.compose_service)
      running = c != nil && normalize_warm_list_state(c) == "running"
      cid = if(c, do: c["Id"], else: nil)
      in_warm = is_binary(cid) && ClosedAgentWarmRegistry.member?(cid) && running
      wl = egress_workload_for_port(egress_snap, entry.proxy_port)

      %{
        entry: entry,
        container: c,
        running: running,
        container_id: cid,
        in_warm_registry: in_warm,
        egress_workload: wl
      }
    end)
  end

  defp refresh_warm_machine_assigns(socket) do
    socket =
      socket
      |> assign(:warm_machines, fetch_warm_machines_merged())

    socket =
      if socket.assigns.live_action == :machines do
        assign(socket, :other_agents_rows, fetch_other_agents_rows())
      else
        socket
      end

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
      <.link patch={~p"/oss-agents"} class={nav_tab_class(@active, :oss_agents)}>OSS Agents</.link>
      <.link patch={~p"/morayeel"} class={nav_tab_class(@active, :morayeel)}>Morayeel</.link>
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

  defp engine_version_from_report(%{checks: checks}) do
    case Enum.find(checks, &(&1.id == :docker_engine)) do
      %{status: :pass, detail: detail} ->
        case Regex.run(~r/Engine\s+([\d.]+)/, detail) do
          [_, version] -> version
          _ -> "connected"
        end

      _ ->
        "n/a"
    end
  end

  defp engine_version_from_report(_), do: "n/a"

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
