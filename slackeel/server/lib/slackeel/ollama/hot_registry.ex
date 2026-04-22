defmodule Slackeel.Ollama.HotRegistry do
  @moduledoc """
  Tracks models Slackeel asked Ollama to hold resident (pull + warm + keep_alive).

  Capacity uses the same heuristic as preflight disk margins (`InferenceBudget`) against
  `:inference_memory_budget_gib` — distinct from disk headroom in `Slackeel.Preflight`.
  """
  use GenServer

  alias Slackeel.Ollama.{Config, Control, InferenceBudget}
  alias Slackeel.Preflight

  @name __MODULE__
  @pubsub_topic "slackeel:hot_models"

  def pubsub_topic, do: @pubsub_topic

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: @name)
  end

  @spec snapshot() :: map()
  def snapshot do
    GenServer.call(@name, :snapshot)
  end

  @doc "Mark a manifest tag as wanted hot (pull/warm when under budget)."
  def want(tag) when is_binary(tag), do: GenServer.cast(@name, {:want, tag})

  @doc "Remove want; unloads from Ollama when resident."
  def unwant(tag) when is_binary(tag), do: GenServer.cast(@name, {:unwant, tag})

  @doc """
  Ensures `tag` is loaded (same pipeline as `want/1`). Replies to caller with
  `{:hot_model_ready, ref, :ok | {:error, reason}}` when finished or immediately if already ready.
  """
  def ensure_ready(tag, caller, ref)
      when is_binary(tag) and is_pid(caller) and is_reference(ref) do
    GenServer.cast(@name, {:ensure_ready, tag, caller, ref})
  end

  @doc "Bump LRU hint after a successful chat turn."
  def touch(tag) when is_binary(tag), do: GenServer.cast(@name, {:touch, tag})

  @impl true
  def init(_opts) do
    manifest =
      case Preflight.manifest_ollama_tags() do
        {:ok, tags} -> MapSet.new(tags, &String.trim/1)
        _ -> MapSet.new()
      end

    state = %{
      manifest: manifest,
      entries: %{},
      waiters: %{},
      ollama_ps: []
    }

    {:ok, refresh_ps(state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, public_snapshot(state), state}
  end

  @impl true
  def handle_cast({:want, tag}, state) do
    tag = String.trim(tag)

    if MapSet.member?(state.manifest, tag) do
      state = put_entry_merge(state, tag, %{want: true})
      state = ensure_wanted_and_start(state, tag)
      {:noreply, refresh_ps(state)}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:unwant, tag}, state) do
    tag = String.trim(tag)
    entry = Map.get(state.entries, tag)

    state =
      case entry do
        %{want: true} = e ->
          state = put_entry(state, tag, %{e | want: false})

          cond do
            e.status == :ready ->
              start_unload(state, tag)

            match?({:error, _}, e.status) ->
              drop_entry(state, tag)

            true ->
              state
          end

        _ ->
          state
      end

    {:noreply, refresh_ps(state)}
  end

  def handle_cast({:ensure_ready, tag, pid, ref}, state) do
    tag = String.trim(tag)

    if not MapSet.member?(state.manifest, tag) do
      send(pid, {:hot_model_ready, ref, {:error, :unknown_model}})
      {:noreply, state}
    else
      state = put_entry_merge(state, tag, %{want: true})
      state = push_waiter(state, tag, pid, ref)

      state =
        case Map.get(state.entries, tag) do
          %{status: :ready} = e when e.want ->
            reply_waiter(state, tag, pid, ref, :ok)

          %{status: {:error, _}} ->
            cur = Map.get(state.entries, tag) || default_entry()
            state = put_entry(state, tag, %{cur | status: :idle, want: true})
            ensure_wanted_and_start(state, tag)

          _ ->
            ensure_wanted_and_start(state, tag)
        end

      {:noreply, refresh_ps(state)}
    end
  end

  def handle_cast({:touch, tag}, state) do
    tag = String.trim(tag)

    state =
      case Map.get(state.entries, tag) do
        %{status: :ready} = e ->
          put_entry(state, tag, %{e | last_used: DateTime.utc_now()})

        _ ->
          state
      end

    {:noreply, state}
  end

  def handle_cast({:pipeline_done, tag, result}, state) do
    tag = String.trim(tag)
    entry = Map.get(state.entries, tag)

    state =
      case {entry, result} do
        {nil, _} ->
          state

        {%{want: false}, :ok} ->
          e = %{entry | status: :ready, last_used: DateTime.utc_now()}
          state = put_entry(state, tag, e)
          start_unload(state, tag)

        {%{want: true}, :ok} ->
          e = %{
            entry
            | status: :ready,
              last_used: DateTime.utc_now(),
              load_pct: 100,
              load_status: "ready"
          }

          state = put_entry(state, tag, e)
          state = reply_all_waiters(state, tag, :ok)
          broadcast!(state)

        {%{want: true}, {:error, reason}} ->
          e = %{
            entry
            | status: {:error, reason},
              load_pct: nil,
              load_status: inspect(reason, limit: 60)
          }

          state = put_entry(state, tag, e)
          state = reply_all_waiters(state, tag, {:error, reason})
          broadcast!(state)

        {%{want: false}, {:error, _reason}} ->
          drop_entry(state, tag)

        {_, _} ->
          state
      end

    {:noreply, refresh_ps(state)}
  end

  def handle_cast({:pull_progress, tag, {pct, status}}, state) do
    tag = String.trim(tag)

    state =
      case Map.get(state.entries, tag) do
        %{want: true, status: st} = e when st in [:pulling, :warming] ->
          load_pct = merge_load_pct(e, pct)
          st_label = if is_binary(status), do: status, else: inspect(status, limit: 40)
          put_entry(state, tag, %{e | load_pct: load_pct, load_status: st_label})

        _ ->
          state
      end

    {:noreply, refresh_ps(state) |> broadcast!()}
  end

  def handle_cast({:hot_phase, tag, :warming}, state) do
    tag = String.trim(tag)

    state =
      case Map.get(state.entries, tag) do
        %{want: true, status: :pulling} = e ->
          warm_floor = 88
          lp = if is_integer(e.load_pct), do: max(e.load_pct, warm_floor), else: warm_floor

          put_entry(state, tag, %{
            e
            | status: :warming,
              load_pct: lp,
              load_status: "warming"
          })

        _ ->
          state
      end

    {:noreply, refresh_ps(state) |> broadcast!()}
  end

  def handle_cast({:unloaded, tag}, state) do
    tag = String.trim(tag)
    entry = Map.get(state.entries, tag)

    state =
      case entry do
        %{want: false} ->
          drop_entry(state, tag)

        %{want: true} ->
          # User re-wanted during unload; start again
          ensure_wanted_and_start(state, tag)

        nil ->
          state
      end

    {:noreply, refresh_ps(state)}
  end

  defp run_pipeline(tag, reg) do
    if Config.hot_registry_dry_run?() do
      for p <- [5, 35, 70, 100] do
        GenServer.cast(reg, {:pull_progress, tag, {p, "dry-run"}})
        Process.sleep(45)
      end

      GenServer.cast(reg, {:hot_phase, tag, :warming})
      Process.sleep(45)
      :ok
    else
      cb = fn pct, st -> GenServer.cast(reg, {:pull_progress, tag, {pct, st}}) end

      with {:ok, _} <- Control.pull_stream(tag, cb, verbose: false),
           _ <- GenServer.cast(reg, {:hot_phase, tag, :warming}),
           {:ok, _} <- Control.warm(tag, verbose: false) do
        :ok
      else
        err -> {:error, err}
      end
    end
  end

  defp merge_load_pct(%{load_pct: old}, new) when is_integer(new) do
    base = if is_integer(old), do: max(old, new), else: new
    min(100, base)
  end

  defp merge_load_pct(_, new) when is_integer(new), do: min(100, new)

  defp merge_load_pct(%{load_pct: old}, nil) when is_integer(old), do: old
  defp merge_load_pct(_, nil), do: nil

  defp ensure_wanted_and_start(state, tag) do
    entry = Map.get(state.entries, tag, %{want: false, status: :idle, last_used: nil})

    cond do
      entry.want && entry.status == :ready ->
        reply_all_waiters(state, tag, :ok)
        broadcast!(state)
        state

      entry.want && entry.status in [:pulling, :warming] ->
        broadcast!(state)
        state

      entry.want && entry.status == :idle ->
        case check_headroom(state, tag) do
          :ok ->
            state =
              put_entry(state, tag, %{
                entry
                | status: :pulling,
                  load_pct: 1,
                  load_status: "starting"
              })

            start_pipeline_task(state, tag)

          {:error, :over_budget} ->
            e = %{entry | status: {:error, :over_budget}, want: true}
            state = put_entry(state, tag, e)
            state = reply_all_waiters(state, tag, {:error, :over_budget})
            broadcast!(state)
            state
        end

      true ->
        state
    end
  end

  defp check_headroom(state, tag) do
    others =
      for {t, e} <- state.entries,
          t != tag,
          e.want,
          e.status in [:pulling, :warming, :ready, :unloading],
          into: MapSet.new(),
          do: t

    sum_others = others |> MapSet.to_list() |> InferenceBudget.sum_margins()
    need = InferenceBudget.margin_bytes(tag)

    if sum_others + need <= InferenceBudget.budget_bytes(),
      do: :ok,
      else: {:error, :over_budget}
  end

  defp start_pipeline_task(state, tag) do
    me = self()

    {:ok, _} =
      Task.Supervisor.start_child(Slackeel.Ollama.HotTaskSupervisor, fn ->
        res = run_pipeline(tag, me)
        GenServer.cast(me, {:pipeline_done, tag, normalize_pipeline_result(res)})
      end)

    broadcast!(state)
    state
  end

  defp normalize_pipeline_result(:ok), do: :ok
  defp normalize_pipeline_result({:error, _} = e), do: e
  defp normalize_pipeline_result(other), do: {:error, other}

  defp start_unload(state, tag) do
    me = self()
    entry = Map.get(state.entries, tag)

    state =
      case entry do
        %{status: :ready} = e ->
          put_entry(state, tag, %{
            e
            | status: :unloading,
              load_pct: nil,
              load_status: "unloading"
          })

        _ ->
          state
      end

    {:ok, _} =
      Task.Supervisor.start_child(Slackeel.Ollama.HotTaskSupervisor, fn ->
        unless Config.hot_registry_dry_run?(), do: Control.unload(tag, verbose: false)
        GenServer.cast(me, {:unloaded, tag})
      end)

    broadcast!(state)
    state
  end

  defp refresh_ps(state) do
    ps =
      case Control.ps() do
        {:ok, models} -> models
        _ -> []
      end

    %{state | ollama_ps: ps}
  end

  defp broadcast!(state) do
    Phoenix.PubSub.broadcast(
      Slackeel.PubSub,
      @pubsub_topic,
      {:hot_models, public_snapshot(state)}
    )

    state
  end

  defp public_snapshot(state) do
    reserved =
      for {t, e} <- state.entries,
          e.want,
          e.status in [:pulling, :warming, :ready, :unloading],
          do: t

    used = InferenceBudget.sum_margins(reserved)

    rows =
      Enum.map(state.entries, fn {t, e} ->
        %{
          tag: t,
          want: e.want,
          status: e.status,
          margin_bytes: InferenceBudget.margin_bytes(t),
          last_used: Map.get(e, :last_used),
          load_pct: Map.get(e, :load_pct),
          load_status: Map.get(e, :load_status),
          unload_busy: e.status == :unloading
        }
      end)
      |> Enum.sort_by(& &1.tag)

    %{
      budget_bytes: InferenceBudget.budget_bytes(),
      used_bytes: used,
      rows: rows,
      ollama_ps: state.ollama_ps
    }
  end

  defp put_entry(state, tag, entry) do
    %{state | entries: Map.put(state.entries, tag, Map.merge(default_entry(), entry))}
  end

  defp put_entry_merge(state, tag, fields) do
    cur = Map.get(state.entries, tag, default_entry())
    put_entry(state, tag, Map.merge(cur, fields))
  end

  defp default_entry do
    %{want: false, status: :idle, last_used: nil, load_pct: nil, load_status: nil}
  end

  defp drop_entry(state, tag) do
    waiters = Map.delete(state.waiters, tag)
    %{state | entries: Map.delete(state.entries, tag), waiters: waiters}
  end

  defp push_waiter(state, tag, pid, ref) do
    q = Map.get(state.waiters, tag, [])
    %{state | waiters: Map.put(state.waiters, tag, [{pid, ref} | q])}
  end

  defp reply_waiter(state, tag, pid, ref, inner) do
    send(pid, {:hot_model_ready, ref, inner})
    q = Map.get(state.waiters, tag, []) |> Enum.reject(fn {p, r} -> p == pid and r == ref end)
    %{state | waiters: Map.put(state.waiters, tag, q)}
  end

  defp reply_all_waiters(state, tag, inner) do
    for {pid, ref} <- Map.get(state.waiters, tag, []) do
      send(pid, {:hot_model_ready, ref, inner})
    end

    %{state | waiters: Map.delete(state.waiters, tag)}
  end
end
