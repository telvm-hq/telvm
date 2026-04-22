defmodule SlackeelWeb.ChatLive do
  @moduledoc """
  Multi-model thread: warm-model buttons or last `@tag` in the outgoing message selects Ollama; prior messages are context.
  """
  use SlackeelWeb, :live_view

  alias Slackeel.Chat
  alias Slackeel.Ollama.{ChatStream, HotRegistry, SseOpenAI}
  alias Slackeel.Preflight
  alias Slackeel.Preflight.DiskDuo

  @impl true
  def mount(_params, session, socket) do
    owner_key = session["chat_owner_id"] || session[:chat_owner_id]

    if owner_key == nil or owner_key == "" do
      raise "missing chat_owner_id in session; EnsureChatOwner plug must run before LiveView"
    end

    manifest_tags =
      case Preflight.manifest_ollama_tags() do
        {:ok, tags} -> tags |> Enum.map(&String.trim/1) |> Enum.uniq() |> Enum.sort()
        _ -> []
      end

    hot = HotRegistry.snapshot()

    socket =
      socket
      |> assign(:page_title, "Chat")
      |> assign(:owner_key, owner_key)
      |> assign(:chat_view, :index)
      |> assign(:conversation, nil)
      |> assign(:conversation_id, nil)
      |> assign(:conversations, [])
      |> assign(:messages, [])
      |> assign(:input, "")
      |> assign(:sse_buf, "")
      |> assign(:pending, nil)
      |> assign(:hot_snapshot, hot)
      |> assign(:default_model, default_model_from_hot(hot))
      |> assign(:selected_model, nil)
      |> assign(:manifest_tags, manifest_tags)
      |> assign(:mention, %{open?: false, query: "", suggestions: []})
      |> load_preflight()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Slackeel.PubSub, HotRegistry.pubsub_topic())
      Phoenix.PubSub.subscribe(Slackeel.PubSub, Chat.chat_owner_topic(owner_key))
    end

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    owner_key = socket.assigns.owner_key

    socket =
      case Map.get(params, "id") do
        id when is_binary(id) and id != "" ->
          case Chat.get_conversation(owner_key, id) do
            {:ok, conv} ->
              msgs = Chat.messages_for_liveview(id)
              convs = Chat.list_conversations(owner_key)

              socket
              |> assign(:chat_view, :thread)
              |> assign(:conversation, conv)
              |> assign(:conversation_id, id)
              |> assign(:conversations, convs)
              |> assign(:messages, msgs)
              |> assign(:page_title, conv.title || "Chat")

            {:error, _} ->
              socket
              |> put_flash(:error, "Conversation not found.")
              |> push_navigate(to: ~p"/chat", replace: true)
          end

        _ ->
          convs = Chat.list_conversations(owner_key)

          socket
          |> assign(:chat_view, :index)
          |> assign(:conversation, nil)
          |> assign(:conversation_id, nil)
          |> assign(:conversations, convs)
          |> assign(:messages, [])
          |> assign(:page_title, "Chat")
      end

    {:noreply, assign_disk_duo(socket)}
  end

  defp load_preflight(socket) do
    socket =
      case Preflight.snapshot() do
        {:ok, snap} ->
          assign(socket, snapshot: snap, error: nil, refreshed_at: DateTime.utc_now())

        {:error, reason} ->
          assign(socket, snapshot: nil, error: inspect(reason), refreshed_at: DateTime.utc_now())
      end

    assign_disk_duo(socket)
  end

  defp assign_disk_duo(socket) do
    assign(socket, :disk_duo, DiskDuo.load())
  end

  defp default_model_from_hot(%{rows: rows}) do
    rows
    |> Enum.find(fn r -> r.want && r.status == :ready end)
    |> case do
      %{tag: t} -> t
      _ -> nil
    end
  end

  defp warm_ready_tags(%{rows: rows}) do
    rows
    |> Enum.filter(fn r -> r.want && r.status == :ready end)
    |> Enum.map(& &1.tag)
    |> Enum.sort()
  end

  defp warm_ready_tags(_), do: []

  @impl true
  def handle_info({:chat_conversation_titled, id, new_title}, socket) when is_binary(new_title) do
    id_str = to_string(id)
    owner_key = socket.assigns.owner_key
    convs = Chat.list_conversations(owner_key)

    socket = assign(socket, :conversations, convs)

    socket =
      if id_str == socket.assigns.conversation_id do
        case Chat.get_conversation(owner_key, id_str) do
          {:ok, c} ->
            socket
            |> assign(:conversation, c)
            |> assign(:page_title, c.title || new_title)

          _ ->
            socket
        end
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:hot_models, snap}, socket) when is_map(snap) do
    warm = warm_ready_tags(snap)

    selected =
      case socket.assigns[:selected_model] do
        t when is_binary(t) ->
          if(t in warm, do: t, else: nil)

        _ ->
          nil
      end

    socket =
      socket
      |> assign(:hot_snapshot, snap)
      |> assign(:default_model, default_model_from_hot(snap))
      |> assign(:selected_model, selected)
      |> assign(:disk_duo, DiskDuo.load())

    socket =
      if socket.assigns.pending && socket.assigns.pending.phase == :loading do
        push_hot_progress_for_pending(socket, snap)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:hot_model_ready, ref, reply}, socket) do
    case socket.assigns.pending do
      %{ref: ^ref, model: model, assistant_id: aid, api_messages: api_msgs} = pend ->
        case reply do
          :ok ->
            dest = self()

            {:ok, _} =
              Task.Supervisor.start_child(Slackeel.Ollama.HotTaskSupervisor, fn ->
                ChatStream.run(dest, pend.stream_ref, model, api_msgs)
              end)

            {:noreply,
             socket
             |> assign(:pending, %{pend | phase: :streaming})
             |> assign(:sse_buf, "")
             |> push_event("hot_model_phase", %{
               tag: model,
               phase: "streaming",
               load_pct: 100,
               unload_busy: false,
               ollama_status: "streaming"
             })}

          {:error, reason} ->
            _ = Chat.update_message_content!(aid, "[load failed]")

            {:noreply,
             socket
             |> put_flash(:error, "Model not ready: #{inspect(reason)}")
             |> assign(:messages, mark_assistant(socket.assigns.messages, aid, "[load failed]"))
             |> assign(:pending, nil)
             |> assign(:sse_buf, "")}
        end

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:ollama_chat_sse, stream_ref, data}, socket) do
    case socket.assigns.pending do
      %{stream_ref: ^stream_ref, assistant_id: aid} = pend ->
        {deltas, buf} = SseOpenAI.drain(socket.assigns.sse_buf <> data)

        content =
          socket.assigns.messages
          |> assistant_content(aid)
          |> Kernel.<>(Enum.join(deltas, ""))

        {:noreply,
         socket
         |> assign(:sse_buf, buf)
         |> assign(:messages, set_assistant_content(socket.assigns.messages, aid, content))
         |> push_event("hot_model_phase", %{tag: pend.model, phase: "streaming"})}

      _ ->
        {:noreply, socket}
    end
  end

  def handle_info({:ollama_chat_done, stream_ref, result}, socket) do
    case socket.assigns.pending do
      %{stream_ref: ^stream_ref, model: model, assistant_id: aid} = pend ->
        HotRegistry.touch(model)

        socket =
          case result do
            :ok ->
              final =
                socket.assigns.messages
                |> assistant_content(aid)

              _ = Chat.update_message_content!(aid, final)

              _ =
                Chat.schedule_suggest_conversation_title!(
                  socket.assigns.owner_key,
                  socket.assigns.conversation_id,
                  model
                )

              socket
              |> assign(:pending, nil)
              |> assign(:sse_buf, "")

            {:error, reason} ->
              cur = assistant_content(socket.assigns.messages, aid)

              msg =
                if cur == "",
                  do: "[stream failed: #{inspect(reason)}]",
                  else: cur <> "\n\n[stream failed: #{inspect(reason)}]"

              _ = Chat.update_message_content!(aid, msg)

              socket
              |> put_flash(:error, "Stream error")
              |> assign(:messages, set_assistant_content(socket.assigns.messages, aid, msg))
              |> assign(:pending, nil)
              |> assign(:sse_buf, "")
          end

        {:noreply,
         push_event(socket, "hot_model_phase", %{
           tag: pend.model,
           phase: "ready",
           load_pct: 100,
           unload_busy: false,
           ollama_status: "done"
         })}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("set_input", params, socket) do
    v = Map.get(params, "content", "") |> to_string()

    mention =
      mention_from_input(v, socket.assigns.manifest_tags)

    {:noreply,
     socket
     |> assign(:input, v)
     |> assign(:mention, mention)}
  end

  @impl true
  def handle_event("pick_model", %{"tag" => tag}, socket) when is_binary(tag) do
    tag = String.trim(tag)
    warm = warm_ready_tags(socket.assigns.hot_snapshot)

    if tag in warm do
      {:noreply, assign(socket, :selected_model, tag)}
    else
      {:noreply, put_flash(socket, :error, "That model is not warm on the runner right now.")}
    end
  end

  def handle_event("pick_model", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("clear_model_pick", _params, socket) do
    {:noreply, assign(socket, :selected_model, nil)}
  end

  @impl true
  def handle_event("new_chat", _params, socket) do
    owner_key = socket.assigns.owner_key

    case Chat.create_conversation(owner_key, %{title: Chat.default_conversation_title(owner_key)}) do
      {:ok, conv} ->
        {:noreply, push_navigate(socket, to: ~p"/chat/#{conv.id}")}

      {:error, changeset} ->
        {:noreply,
         put_flash(socket, :error, "Could not start a conversation: #{inspect(changeset.errors)}")}
    end
  end

  @impl true
  def handle_event("mention_pick", %{"tag" => picked}, socket) when is_binary(picked) do
    text = replace_mention_suffix(socket.assigns.input, picked)

    {:noreply,
     socket
     |> assign(:input, text)
     |> assign(:mention, %{open?: false, query: "", suggestions: []})}
  end

  @impl true
  def handle_event("send", %{"content" => body}, socket) do
    body = String.trim(to_string(body))

    if body == "" do
      {:noreply, socket}
    else
      model =
        case last_at_model(body) do
          nil ->
            socket.assigns[:selected_model] || socket.assigns.default_model

          m ->
            m
        end

      if model == nil do
        {:noreply,
         put_flash(
           socket,
           :error,
           "Pick a warm model above, add @tag in your message, or hot-load on /models."
         )}
      else
        cond do
          socket.assigns.pending != nil ->
            {:noreply, put_flash(socket, :error, "Wait for the current reply to finish.")}

          socket.assigns.conversation_id == nil ->
            {:noreply,
             put_flash(
               socket,
               :error,
               "Open a conversation or start a new one from the list."
             )}

          true ->
            conv_id = socket.assigns.conversation_id

            case Chat.append_user_and_assistant(conv_id, body, model) do
              {:ok, {_user_map, assistant_map}} ->
                msgs = Chat.messages_for_liveview(conv_id)
                api_messages = msgs |> Enum.map(&%{"role" => &1.role, "content" => &1.content})

                ref = make_ref()
                stream_ref = make_ref()

                HotRegistry.ensure_ready(model, self(), ref)

                {:noreply,
                 socket
                 |> assign(:messages, msgs)
                 |> assign(:conversations, Chat.list_conversations(socket.assigns.owner_key))
                 |> assign(:input, "")
                 |> assign(:sse_buf, "")
                 |> assign(:mention, %{open?: false, query: "", suggestions: []})
                 |> assign(:pending, %{
                   ref: ref,
                   stream_ref: stream_ref,
                   model: model,
                   assistant_id: assistant_map.id,
                   api_messages: api_messages,
                   phase: :loading
                 })
                 |> push_event("hot_model_phase", %{
                   tag: model,
                   phase: "loading",
                   load_pct: 2,
                   unload_busy: false,
                   ollama_status: "queued"
                 })}

              {:error, reason} ->
                {:noreply,
                 put_flash(socket, :error, "Could not save message: #{inspect(reason)}")}
            end
        end
      end
    end
  end

  defp last_at_model(text) do
    case Regex.scan(~r/@([\w.\-:]+)/u, text, capture: :all_but_first) do
      [] ->
        nil

      caps ->
        caps |> List.last() |> hd()
    end
  end

  defp assistant_content(messages, aid) do
    case Enum.find(messages, &(&1.id == aid)) do
      %{content: c} when is_binary(c) -> c
      _ -> ""
    end
  end

  defp set_assistant_content(messages, aid, content) do
    Enum.map(messages, fn m ->
      if m.id == aid, do: %{m | content: content}, else: m
    end)
  end

  defp mark_assistant(messages, aid, text) do
    set_assistant_content(messages, aid, text)
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :warm_tags, warm_ready_tags(assigns.hot_snapshot))

    ~H"""
    <div
      id="slac-chat-live"
      class="telvm-terminal telvm-console-shell slac-tactical flex min-h-0 flex-1 flex-col gap-3 px-3 py-3 sm:px-4 sm:py-4 lg:flex-row lg:items-stretch"
      phx-hook="HotModelPhase"
      data-chat-pending-model={
        if(@pending && @pending.phase == :loading, do: @pending.model, else: "")
      }
    >
      <aside class="flex max-h-48 shrink-0 flex-col gap-1.5 overflow-y-auto border-b border-[color:var(--telvm-shell-border)] pb-2 font-mono lg:max-h-none lg:w-44 lg:border-b-0 lg:border-r lg:pb-0 lg:pr-3">
        <div class="text-[9px] font-semibold uppercase tracking-[0.14em] text-[var(--telvm-shell-muted)]">
          Conversations
        </div>
        <.link
          patch={~p"/chat"}
          class="block rounded-sm border border-transparent px-2 py-1 text-[10px] text-[var(--telvm-shell-muted)] hover:bg-[color-mix(in_oklch,var(--telvm-shell-elevated)_50%,transparent)]"
        >
          All chats
        </.link>
        <button
          type="button"
          phx-click="new_chat"
          class="btn btn-primary btn-xs rounded-sm font-mono uppercase tracking-wide"
        >
          New chat
        </button>
        <nav class="flex flex-col gap-0.5 text-[10px]">
          <.link
            :for={c <- @conversations}
            patch={~p"/chat/#{c.id}"}
            class={[
              "block truncate rounded-sm border px-2 py-1.5 transition-colors",
              if(@conversation_id == to_string(c.id),
                do:
                  "border-[color:var(--telvm-accent)] bg-[color-mix(in_oklch,var(--telvm-accent)_12%,transparent)] telvm-accent-text",
                else:
                  "border-transparent text-[var(--telvm-shell-fg)] hover:bg-[color-mix(in_oklch,var(--telvm-shell-elevated)_50%,transparent)]"
              )
            ]}
          >
            {c.title || "Untitled"}
          </.link>
        </nav>
      </aside>

      <div class="flex min-h-0 min-w-0 flex-1 flex-col gap-2">
        <div class="shrink-0 font-mono">
          <h1 class="text-xs font-semibold uppercase tracking-wide telvm-accent-text sm:text-sm">
            Chat
          </h1>

          <p class="telvm-muted-xs mt-0.5 line-clamp-2 max-w-xl text-[9px] leading-snug sm:line-clamp-none sm:max-w-lg sm:text-[10px]">
            <span class="font-semibold text-[var(--telvm-shell-fg)]">Warm</span>
            model: buttons or
            <code class="rounded px-0.5" style="background: var(--telvm-input-bg);">@tag</code>
            (last @ wins) ·
            <a href={~p"/models"} class="telvm-accent-text underline-offset-2 hover:underline">
              /models
            </a>
          </p>
        </div>

        <div class="slac-card telvm-verify-card telvm-panel-border flex min-h-0 flex-1 flex-col overflow-hidden border border-[color:var(--telvm-shell-border)] font-mono">
          <div
            id="slac-chat-messages-scroll"
            class="slac-card__body flex min-h-0 flex-1 flex-col gap-2 overflow-y-auto p-2 text-[11px] sm:text-xs"
            phx-hook="ChatFeedScroll"
            data-chat-pending={if is_nil(@pending), do: "false", else: "true"}
          >
            <div
              :if={@chat_view == :index}
              class="telvm-muted-xs py-6 text-center text-[10px] leading-relaxed"
            >
              Pick a conversation on the left or start
              <span class="font-semibold text-[var(--telvm-shell-fg)]">New chat</span>
              .
            </div>

            <div
              :if={@chat_view == :thread && @messages == []}
              class="telvm-muted-xs py-6 text-center text-[10px]"
            >
              No messages yet.
            </div>

            <div :for={m <- @messages} class={"rounded-sm border px-2 py-1.5 #{msg_class(m.role)}"}>
              <div class="mb-0.5 flex flex-wrap items-baseline justify-between gap-x-2 gap-y-0.5 text-[9px] uppercase tracking-wide text-[var(--telvm-shell-muted)]">
                <span class="font-semibold">{m.role}</span>
                <span
                  :if={m.model}
                  class="slac-model-chip shrink-0 truncate"
                  title={
                    if(m.role == "user", do: "Sent to this model", else: "Reply from this model")
                  }
                >
                  {m.model}
                </span>
              </div>

              <div class="whitespace-pre-wrap break-words text-[var(--telvm-shell-fg)]">
                {m.content}
              </div>
            </div>
          </div>

          <div class="shrink-0 border-t border-[color:var(--telvm-shell-border)] p-2">
            <div class="mb-1 text-[9px] font-semibold uppercase tracking-[0.12em] text-[var(--telvm-shell-muted)]">
              Warm &amp; ready
            </div>
            <div :if={@warm_tags == []} class="telvm-muted-xs text-[9px] leading-relaxed">
              No models resident on the runner.
              <a href={~p"/models"} class="telvm-accent-text underline-offset-2 hover:underline">
                /models
              </a>
              → Hot, or type @tag if not warm yet.
            </div>
            <div :if={@warm_tags != []} class="flex flex-wrap gap-1.5">
              <button
                :for={t <- @warm_tags}
                type="button"
                phx-click="pick_model"
                phx-value-tag={t}
                class={[
                  "slac-model-chip slac-model-chip--picker max-w-none font-mono text-[10px] sm:text-[11px]",
                  @selected_model == t && "slac-model-chip--picker-active"
                ]}
                title={"Use #{t} for the next send (unless you override with @ in the message)"}
              >
                {t}
              </button>
            </div>
            <div
              :if={@selected_model}
              class="telvm-muted-xs mt-1 flex flex-wrap items-baseline gap-x-2 gap-y-0.5 text-[8px]"
            >
              <span>
                Next send →
                <span class="font-mono text-[var(--telvm-shell-fg)]">{@selected_model}</span>
                unless overridden by @ in text.
              </span>
              <button
                type="button"
                phx-click="clear_model_pick"
                class="shrink-0 font-mono text-[8px] font-semibold uppercase tracking-wide telvm-accent-text underline-offset-2 hover:underline"
              >
                Clear pick
              </button>
            </div>
          </div>

          <form
            :if={@chat_view == :thread}
            class="shrink-0 border-t border-[color:var(--telvm-shell-border)] p-2"
            phx-submit="send"
          >
            <div
              :if={@pending && @pending.phase == :loading}
              class="mb-2 rounded-sm border px-2 py-1.5 font-mono text-[9px]"
              style="border-color: var(--telvm-shell-border); background: color-mix(in oklch, var(--telvm-shell-elevated) 55%, transparent);"
            >
              <div class="flex flex-wrap items-center justify-between gap-x-2 gap-y-0.5">
                <span class="font-semibold uppercase tracking-wide telvm-accent-text">
                  Loading model
                </span>
                <span
                  class="slac-model-chip max-w-[min(100%,14rem)] shrink-0 truncate"
                  title={@pending.model}
                >
                  {@pending.model}
                </span>
              </div>
              <div
                class="telvm-muted-xs mt-0.5 truncate"
                title={pending_status_title(@hot_snapshot, @pending.model)}
              >
                {pending_status_title(@hot_snapshot, @pending.model)}
              </div>
              <div class="telvm-progress-track mt-1.5">
                <div
                  data-chat-load-fill
                  class={[
                    "telvm-progress-fill",
                    pending_chat_fill_class(@hot_snapshot, @pending.model)
                  ]}
                  style={pending_chat_fill_style(@hot_snapshot, @pending.model)}
                >
                </div>
              </div>
            </div>

            <label class="sr-only" for="chat-input">Message</label>
            <div class="relative mb-2">
              <textarea
                id="chat-input"
                name="content"
                phx-change="set_input"
                rows="3"
                autocomplete="off"
                class="telvm-input w-full resize-y rounded-sm border px-2 py-1.5 font-mono text-[11px]"
                style="border-color: var(--telvm-shell-border); background: var(--telvm-input-bg); color: var(--telvm-shell-fg);"
                placeholder="Pick a warm model above, or type @tag in your message…"
              >{@input}</textarea>
              <div
                :if={@mention.open? && @mention.suggestions != []}
                class="absolute left-0 right-0 top-full z-20 mt-1 max-h-48 overflow-y-auto rounded-sm border font-mono text-[10px] shadow-md"
                style="border-color: var(--telvm-shell-border); background: var(--telvm-shell-elevated); color: var(--telvm-shell-fg);"
              >
                <ul class="divide-y divide-[color-mix(in_oklch,var(--telvm-shell-border)_55%,transparent)]">
                  <li :for={opt <- @mention.suggestions} class="leading-tight">
                    <button
                      type="button"
                      phx-click="mention_pick"
                      phx-value-tag={opt}
                      class="w-full px-2 py-1.5 text-left hover:bg-[color-mix(in_oklch,var(--telvm-accent)_14%,transparent)]"
                    >
                      @{opt}
                    </button>
                  </li>
                </ul>
              </div>
            </div>
            <div class="flex flex-wrap items-center justify-end gap-2">
              <button
                type="submit"
                class="btn btn-primary btn-xs sm:btn-sm rounded-sm font-mono uppercase tracking-wide"
                disabled={@pending != nil}
              >
                Send
              </button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp msg_class("user"),
    do:
      "border-[color:var(--telvm-shell-border)] bg-[color-mix(in_oklch,var(--telvm-shell-elevated)_40%,transparent)]"

  defp msg_class(_),
    do:
      "border-[color:color-mix(in_oklch,var(--telvm-accent)_35%,var(--telvm-shell-border))] bg-[color-mix(in_oklch,var(--telvm-accent)_12%,transparent)]"

  defp push_hot_progress_for_pending(socket, snap) do
    case socket.assigns.pending do
      %{phase: :loading, model: model} ->
        row = Enum.find(snap.rows, &(&1.tag == model))

        if row do
          push_event(socket, "hot_model_phase", %{
            tag: model,
            phase: "loading",
            load_pct: row.load_pct,
            unload_busy: row.unload_busy == true,
            ollama_status: row.load_status
          })
        else
          socket
        end

      _ ->
        socket
    end
  end

  defp mention_from_input(text, tags) when is_binary(text) and is_list(tags) do
    case Regex.run(~r/@([\w.\-:]*)$/u, text) do
      nil ->
        %{open?: false, query: "", suggestions: []}

      [_, q] ->
        sugs = filter_mentions(tags, q)
        %{open?: true, query: q, suggestions: sugs}
    end
  end

  defp mention_from_input(_, _), do: %{open?: false, query: "", suggestions: []}

  defp filter_mentions(tags, "") do
    Enum.take(tags, 15)
  end

  defp filter_mentions(tags, q) when is_binary(q) do
    qd = String.downcase(q)

    primary =
      Enum.filter(tags, fn t -> t |> String.downcase() |> String.starts_with?(qd) end)

    secondary =
      if primary == [] and q != "" do
        Enum.filter(tags, fn t -> String.contains?(String.downcase(t), qd) end)
      else
        []
      end

    primary
    |> Kernel.++(secondary)
    |> Enum.uniq()
    |> Enum.take(15)
  end

  defp replace_mention_suffix(text, picked) when is_binary(text) and is_binary(picked) do
    Regex.replace(~r/@([\w.\-:]*)$/u, text, "@#{picked} ")
  end

  defp pending_row(snap, model) when is_map(snap) and is_binary(model) do
    Enum.find(snap.rows, &(&1.tag == model))
  end

  defp pending_status_title(snap, model) do
    case pending_row(snap, model) do
      %{load_status: s} when is_binary(s) and s != "" ->
        s

      %{status: :pulling} ->
        "Pulling weights…"

      %{status: :warming} ->
        "Warming runner…"

      _ ->
        "Preparing…"
    end
  end

  defp pending_chat_fill_class(snap, model) do
    case pending_row(snap, model) do
      %{load_pct: p} when is_integer(p) -> ""
      _ -> "telvm-progress-fill--indeterminate"
    end
  end

  defp pending_chat_fill_style(snap, model) do
    case pending_row(snap, model) do
      %{load_pct: p} when is_integer(p) -> "width: #{p}%;"
      _ -> "width: 36%;"
    end
  end
end
