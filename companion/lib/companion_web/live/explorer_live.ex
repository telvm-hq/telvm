defmodule CompanionWeb.ExplorerLive do
  @moduledoc """
  Dedicated read-only filesystem explorer for a running lab container.

  Opened via the **monaco** link next to ports on the machines table:

      /explore/<container-id>

  Each browser tab is its own isolated BEAM process. The LiveView reaches into
  the container via `docker exec` (ls, cat) — no HTTP port required. Works for
  any image regardless of whether it serves HTTP.

  When `/workspace` exists (e.g. bind mount from the agent API), the tree starts
  there and cannot navigate above it; otherwise the container root `/` is used.

  Monaco Editor is loaded from CDN via the MonacoExplorer JS hook (app.js).
  """

  use CompanionWeb, :live_view

  alias Companion.Docker

  @impl true
  def mount(%{"id" => container_id}, _session, socket) do
    container_name = resolve_name(container_id)
    explorer_root = resolve_explorer_root(container_id)

    socket =
      socket
      |> assign(:page_title, "monaco · #{container_name}")
      |> assign(:container_id, container_id)
      |> assign(:container_name, container_name)
      |> assign(:explorer_root, explorer_root)
      |> assign(:path, explorer_root)
      |> assign(:entries, [])
      |> assign(:content, nil)
      |> assign(:content_path, nil)
      |> assign(:loading, false)
      |> assign(:error, nil)

    # Load listing on every mount (including static render) so first paint can populate.
    fetch_entries(container_id, explorer_root)

    {:ok, assign(socket, :loading, true)}
  end

  # ---------------------------------------------------------------------------
  # handle_info — Task results
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:explorer_entries, path, entries}, socket) do
    {:noreply,
     socket
     |> assign(:path, path)
     |> assign(:entries, entries)
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  def handle_info({:explorer_content, file_path, content}, socket) do
    {:noreply,
     socket
     |> assign(:content, content)
     |> assign(:content_path, file_path)
     |> assign(:loading, false)
     |> assign(:error, nil)}
  end

  def handle_info({:explorer_error, reason}, socket) do
    {:noreply,
     socket
     |> assign(:loading, false)
     |> assign(:error, inspect(reason))}
  end

  # ---------------------------------------------------------------------------
  # handle_event — navigation
  # ---------------------------------------------------------------------------

  @impl true
  def handle_event("explore_path", %{"path" => path}, socket) do
    cid = socket.assigns.container_id
    root = socket.assigns.explorer_root
    path = clamp_under_root(path, root)
    fetch_entries(cid, path)
    {:noreply, assign(socket, loading: true, error: nil)}
  end

  def handle_event("explore_file", %{"path" => file_path}, socket) do
    cid = socket.assigns.container_id
    root = socket.assigns.explorer_root
    file_path = clamp_under_root(file_path, root)
    pid = self()

    Task.start(fn ->
      docker = Docker.impl()

      case docker.container_exec(cid, ["cat", file_path], []) do
        {:ok, content} -> send(pid, {:explorer_content, file_path, content})
        {:error, reason} -> send(pid, {:explorer_error, reason})
      end
    end)

    {:noreply, assign(socket, loading: true, error: nil)}
  end

  # ---------------------------------------------------------------------------
  # Template
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen flex flex-col bg-zinc-950 text-zinc-200 font-mono overflow-hidden">
      <%!-- Header bar --%>
      <div class="flex items-center justify-between px-4 py-2 border-b border-zinc-800 bg-zinc-900/80 shrink-0">
        <div class="flex items-center gap-3 min-w-0">
          <span class="text-violet-400/90 text-[10px] tracking-wide shrink-0">monaco</span>
          <span class="text-zinc-300 text-[11px] truncate">{@container_name}</span>
          <span class="text-zinc-600 text-[10px]">·</span>
          <span class="text-zinc-500 text-[10px] truncate">{@path}</span>
        </div>
        <div class="flex items-center gap-3 shrink-0">
          <span :if={@loading} class="text-zinc-500 text-[10px] animate-pulse">loading…</span>
          <span :if={@error} class="text-rose-400 text-[10px]" title={@error}>error</span>
          <a
            href="/machines"
            class="px-2 py-0.5 text-[10px] rounded-sm border border-zinc-700 text-zinc-500 hover:text-zinc-300 hover:border-zinc-500 transition-colors uppercase tracking-wide"
          >
            ← machines
          </a>
        </div>
      </div>

      <%!-- Two-panel body --%>
      <div class="flex flex-1 min-h-0">
        <%!-- File tree panel --%>
        <div class="w-60 shrink-0 border-r border-zinc-800 overflow-y-auto bg-black/20 py-1">
          <%!-- Parent directory link --%>
          <button
            :if={@path != @explorer_root}
            type="button"
            phx-click="explore_path"
            phx-value-path={parent_clamped(@path, @explorer_root)}
            class="flex items-center gap-2 w-full px-3 py-1 text-[10px] text-zinc-500 hover:text-zinc-300 hover:bg-zinc-800/50 transition-colors"
          >
            <span class="text-zinc-700">↑</span>
            <span>..</span>
          </button>

          <%!-- Directory entries (dirs first) --%>
          <div :for={entry <- @entries}>
            <button
              :if={entry.type == :dir}
              type="button"
              phx-click="explore_path"
              phx-value-path={join_path(@path, entry.name)}
              class="flex items-center gap-2 w-full px-3 py-1 text-[10px] text-cyan-400/80 hover:text-cyan-300 hover:bg-zinc-800/50 transition-colors text-left"
            >
              <span class="text-zinc-600">▸</span>
              <span class="truncate">{entry.name}/</span>
            </button>
            <button
              :if={entry.type != :dir}
              type="button"
              phx-click="explore_file"
              phx-value-path={join_path(@path, entry.name)}
              class={[
                "flex items-center gap-2 w-full px-3 py-1 text-[10px] transition-colors hover:bg-zinc-800/50 text-left",
                @content_path == join_path(@path, entry.name) &&
                  "text-amber-300 bg-zinc-800/40" ||
                  "text-zinc-400 hover:text-zinc-200"
              ]}
            >
              <span class="text-zinc-700">·</span>
              <span class="truncate">{entry.name}</span>
            </button>
          </div>

          <div
            :if={@entries == [] and not @loading}
            class="px-3 py-3 text-zinc-700 text-[10px] italic"
          >
            empty
          </div>
        </div>

        <%!-- Monaco panel --%>
        <div class="flex-1 min-w-0 flex flex-col">
          <%!-- File path breadcrumb --%>
          <div
            :if={@content_path}
            class="px-4 py-1.5 border-b border-zinc-800 bg-zinc-900/40 text-zinc-500 text-[9px] shrink-0"
          >
            {@content_path}
          </div>

          <%!-- Placeholder before file selected --%>
          <div
            :if={is_nil(@content) and not @loading}
            class="flex-1 flex flex-col items-center justify-center gap-2 text-zinc-700"
          >
            <span class="text-[11px]">select a file to view</span>
            <span class="text-[10px] text-zinc-800">{@container_name}</span>
          </div>

          <%!-- Loading placeholder --%>
          <div
            :if={is_nil(@content) and @loading}
            class="flex-1 flex items-center justify-center text-zinc-700 text-[10px] animate-pulse"
          >
            loading…
          </div>

          <%!-- Monaco editor — hook sets it up once content arrives --%>
          <div
            :if={@content != nil}
            id="monaco-explorer"
            phx-hook="MonacoExplorer"
            data-content={@content}
            data-content-path={@content_path}
            class="flex-1"
          />
        </div>
      </div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp fetch_entries(container_id, path) do
    pid = self()

    Task.start(fn ->
      docker = Docker.impl()

      case docker.container_exec(container_id, ["ls", "-la", path], []) do
        {:ok, output} ->
          entries = parse_ls_output(output)
          send(pid, {:explorer_entries, path, entries})

        {:error, reason} ->
          send(pid, {:explorer_error, reason})
      end
    end)
  end

  defp resolve_name(container_id) do
    docker = Docker.impl()

    case docker.container_inspect(container_id) do
      {:ok, info} ->
        case info["Name"] do
          n when is_binary(n) -> String.trim_leading(n, "/")
          _ -> String.slice(container_id, 0, 12)
        end

      {:error, _} ->
        String.slice(container_id, 0, 12)
    end
  end

  defp resolve_explorer_root(container_id) do
    docker = Docker.impl()

    case docker.container_exec(container_id, ["ls", "-la", "/workspace"], []) do
      {:ok, _} -> "/workspace"
      {:error, _} -> "/"
    end
  end

  defp clamp_under_root(path, "/"), do: path

  defp clamp_under_root(path, root) do
    cond do
      path == root -> path
      String.starts_with?(path, root <> "/") -> path
      true -> root
    end
  end

  defp parent_clamped(path, root) when path == root, do: root

  defp parent_clamped(path, root) do
    p = parent_path(path)

    cond do
      root == "/" -> p
      p == "/" -> root
      String.starts_with?(p, root <> "/") -> p
      p == root -> root
      true -> root
    end
  end

  defp parent_path("/"), do: "/"

  defp parent_path(path) do
    case String.split(path, "/", trim: true) do
      [] -> "/"
      parts -> "/" <> Enum.join(Enum.drop(parts, -1), "/")
    end
  end

  defp join_path("/", name), do: "/" <> name
  defp join_path(path, name), do: String.trim_trailing(path, "/") <> "/" <> name

  # Parse `ls -la` output into a list of entry maps.
  # Each entry: %{name, type (:dir | :file | :link | :other), size, permissions}
  defp parse_ls_output(output) when is_binary(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.drop_while(&String.starts_with?(&1, "total"))
    |> Enum.flat_map(fn line ->
      parts = String.split(line, ~r/\s+/, parts: 9)

      case parts do
        [perms, _links, _user, _group, size, _month, _day, _time, name]
        when name not in [".", ".."] ->
          type =
            cond do
              String.starts_with?(perms, "d") -> :dir
              String.starts_with?(perms, "l") -> :link
              String.starts_with?(perms, "-") -> :file
              true -> :other
            end

          [%{name: name, type: type, size: size, permissions: perms}]

        _ ->
          []
      end
    end)
    |> Enum.sort_by(fn e -> {if(e.type == :dir, do: 0, else: 1), e.name} end)
  end
end
