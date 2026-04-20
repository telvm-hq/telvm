defmodule Slackeel.Ollama.VerifyPipeline do
  @moduledoc false

  # Shared Ollama verify orchestration for Mix (`VerifyRunner`) and LiveView (`PreflightLive`).
  # Modes:
  # - `:phased` — pull all (bounded concurrency) → probe all → unload all
  # - `:serial` — per model: pull → probe → unload, strictly one model at a time

  alias Slackeel.Ollama.{Config, Control, IntegrationVerify}

  @doc """
  Returns `[{model, {:ok, reply, meta} | {:error, reason}}]` in manifest order (`meta` from `Chat.completion/3`).

  Options:
  - `:mode` — `:phased` (default) | `:serial`
  - `:pull`, `:unload` — booleans (default true)
  - `:retries` — probe retries (default 3)
  - `:verbose` — forwarded to HTTP clients
  - `:pull_parallel` — only `:phased` pull phase (default 1)
  - `:probe_parallel` — only `:phased` probe phase
  - `:on_event` — `fn {:notify, term} -> any end` (optional)
  - `:should_continue` — `fn -> boolean end` (optional). If it returns `false` before a model
    cycle, remaining models are skipped (serial mode only). Used for cooperative cancel.
  - `:probe_prompt` — user message string for integration probe (optional; defaults to config)
  """
  def run(models, opts \\ []) when is_list(models) do
    case Keyword.get(opts, :mode, :phased) do
      :serial -> run_serial(models, opts)
      :phased -> run_phased(models, opts)
    end
  end

  defp notify(opts, msg) when is_list(opts) do
    notify(Keyword.get(opts, :on_event), msg)
  end

  defp notify(nil, _msg), do: :ok
  defp notify(fun, msg) when is_function(fun, 1), do: fun.(msg)

  defp log(opts, iodata) when is_list(opts) do
    line = :erlang.iolist_to_binary(iodata)
    notify(opts, {:notify, {:log, line}})
  end

  defp ts do
    DateTime.utc_now() |> Calendar.strftime("%H:%M:%S")
  end

  defp build_runner_opts(opts, verbose?) do
    base = [verbose: verbose?]

    case Keyword.get(opts, :probe_prompt) do
      p when is_binary(p) ->
        case String.trim(p) do
          "" -> base
          trimmed -> Keyword.put(base, :prompt, trimmed)
        end

      _ ->
        base
    end
  end

  defp probe_invoke_opts(runner_opts) do
    Keyword.take(runner_opts, [:verbose, :prompt])
  end

  # --- serial: one model at a time, full lifecycle each ---------------------------------

  defp run_serial(models, opts) do
    pull? = Keyword.get(opts, :pull, true)
    unload? = Keyword.get(opts, :unload, true)
    retries = Keyword.get(opts, :retries, 3)
    verbose? = Keyword.get(opts, :verbose, false)
    should_continue = Keyword.get(opts, :should_continue, fn -> true end)
    runner_opts = build_runner_opts(opts, verbose?)
    pull_timeout = Config.ollama_pull_timeout_ms()
    pull_opts = [verbose: verbose?, receive_timeout: pull_timeout]

    run_cycle = fn model ->
      log(opts, "[#{ts()}] #{model} · cycle · start")
      notify(opts, {:notify, {model, :cycle, :started}})

      result =
        if pull? do
          log(opts, "[#{ts()}] #{model} · pull · POST /api/pull")
          notify(opts, {:notify, {model, :pull, :started}})

          case Control.pull(model, pull_opts) do
            {:ok, _} ->
              log(opts, "[#{ts()}] #{model} · pull · ok")
              notify(opts, {:notify, {model, :pull, :ok}})
              probe_then_maybe_unload(model, unload?, retries, runner_opts, opts)

            {:error, e} ->
              log(opts, "[#{ts()}] #{model} · pull · err #{short_err(e)}")
              notify(opts, {:notify, {model, :pull, {:error, e}}})
              if unload?, do: silent_unload(model, verbose?)
              {model, {:error, {:pull, e}}}
          end
        else
          log(opts, "[#{ts()}] #{model} · pull · skipped")
          probe_then_maybe_unload(model, unload?, retries, runner_opts, opts)
        end

      probe_outcome = elem(result, 1)
      cycle_ok? = match?({:ok, _, _}, probe_outcome)

      log(opts, "[#{ts()}] #{model} · cycle · #{if cycle_ok?, do: "done", else: "fail"}")
      notify(opts, {:notify, {model, :cycle, :done, elem(result, 1)}})
      result
    end

    {rev, stopped?} =
      Enum.reduce(models, {[], false}, fn model, {acc, stopped} ->
        if stopped do
          {acc, true}
        else
          if should_continue.() do
            {[run_cycle.(model) | acc], false}
          else
            log(opts, "[#{ts()}] · verify · stopped by user (remaining models skipped)")
            notify(opts, {:notify, {:log, "[#{ts()}] · verify · stopped by user (remaining models skipped)"}})
            {acc, true}
          end
        end
      end)

    if stopped? do
      log(opts, "[#{ts()}] · verify · run ended early")
    end

    Enum.reverse(rev)
  end

  defp probe_then_maybe_unload(model, unload?, retries, runner_opts, opts) do
    log(opts, "[#{ts()}] #{model} · probe · POST /v1/chat/completions")
    notify(opts, {:notify, {model, :probe, :started}})

    case probe_with_retries(model, retries, runner_opts) do
      {:ok, text, meta} = ok ->
        prev = text |> to_string() |> String.replace("\n", " ") |> String.slice(0, 160)
        tps = meta[:tokens_per_sec]
        tps_note = if tps, do: " · #{tps} tok/s", else: ""
        log(opts, "[#{ts()}] #{model} · probe · ok (#{byte_size(to_string(text))} B)#{tps_note} #{prev}")
        notify(opts, {:notify, {model, :probe, {:ok, text, meta}}})
        if unload? do
          log(opts, "[#{ts()}] #{model} · unload · POST /api/chat keep_alive=0")
          notify(opts, {:notify, {model, :unload, :started}})
          u = Control.unload(model, verbose: Keyword.get(runner_opts, :verbose, false))
          log(opts, "[#{ts()}] #{model} · unload · #{unload_short(u)}")
          notify(opts, {:notify, {model, :unload, unload_notify(u)}})
        else
          log(opts, "[#{ts()}] #{model} · unload · skipped")
        end

        {model, ok}

      {:error, e} = err ->
        log(opts, "[#{ts()}] #{model} · probe · err #{short_err(e)}")
        notify(opts, {:notify, {model, :probe, {:error, e}}})
        if unload?, do: silent_unload(model, Keyword.get(runner_opts, :verbose, false))
        {model, err}
    end
  end

  defp unload_short({:ok, _}), do: "ok"
  defp unload_short({:error, e}), do: "err #{short_err(e)}"
  defp unload_short(other), do: inspect(other, limit: 80)

  defp short_err({:http, s, _}), do: "HTTP #{s}"
  defp short_err({:api, e}), do: inspect(e, limit: 80)
  defp short_err(%Req.TransportError{} = e), do: inspect(e.reason, limit: 40)
  defp short_err(e) when is_binary(e), do: String.slice(e, 0, 120)
  defp short_err(e), do: inspect(e, limit: 120)

  defp probe_short({:ok, text, meta}) do
    prev = text |> to_string() |> String.replace("\n", " ") |> String.slice(0, 120)
    tps = meta[:tokens_per_sec]
    suf = if tps, do: " · #{tps} tok/s", else: ""
    "ok#{suf} · #{prev}"
  end

  defp probe_short({:ok, text}) do
    prev = text |> to_string() |> String.replace("\n", " ") |> String.slice(0, 120)
    "ok · #{prev}"
  end

  defp probe_short({:error, e}), do: "err #{short_err(e)}"
  defp probe_short(other), do: inspect(other, limit: 80)

  defp unload_notify({:ok, _}), do: :ok
  defp unload_notify({:error, e}), do: {:error, e}

  defp silent_unload(model, verbose?) do
    _ = Control.unload(model, verbose: verbose?)
    :ok
  end

  # --- phased (original behaviour) ------------------------------------------------------

  defp run_phased(models, opts) do
    pull? = Keyword.get(opts, :pull, true)
    unload? = Keyword.get(opts, :unload, true)
    retries = Keyword.get(opts, :retries, 3)
    verbose? = Keyword.get(opts, :verbose, false)
    pull_parallel = Keyword.get(opts, :pull_parallel, 1)
    parallel = Keyword.get(opts, :probe_parallel, Config.integration_verify_max_parallel())
    runner_opts = build_runner_opts(opts, verbose?)
    pull_timeout = Config.ollama_pull_timeout_ms()
    pull_opts = [verbose: verbose?, receive_timeout: pull_timeout]

    prepared =
      if pull? do
        Task.async_stream(
          models,
          fn model ->
            log(opts, "[#{ts()}] #{model} · pull · POST /api/pull")
            notify(opts, {:notify, {model, :pull, :started}})

            case Control.pull(model, pull_opts) do
              {:ok, _} ->
                log(opts, "[#{ts()}] #{model} · pull · ok")
                notify(opts, {:notify, {model, :pull, :ok}})
                {model, :ready}

              {:error, e} ->
                log(opts, "[#{ts()}] #{model} · pull · err #{short_err(e)}")
                notify(opts, {:notify, {model, :pull, {:error, e}}})
                {model, {:pull_failed, e}}
            end
          end,
          max_concurrency: max(1, pull_parallel),
          timeout: pull_timeout + 120_000,
          ordered: true,
          on_timeout: :kill_task
        )
        |> Enum.to_list()
        |> Enum.map(fn
          {:ok, pair} -> pair
          {:exit, reason} -> {"_", {:pull_failed, {:stream_exit, reason}}}
        end)
      else
        Enum.map(models, fn m -> {m, :ready} end)
      end

    stream_timeout =
      max(Config.ollama_chat_timeout_ms() * retries * 2, 300_000)

    rows =
      Task.async_stream(
        prepared,
        fn
          {model, {:pull_failed, e}} ->
            log(opts, "[#{ts()}] #{model} · probe · skipped (pull failed)")
            {model, {:error, {:pull, e}}}

          {model, :ready} ->
            log(opts, "[#{ts()}] #{model} · probe · POST /v1/chat/completions")
            notify(opts, {:notify, {model, :probe, :started}})
            r = probe_with_retries(model, retries, runner_opts)
            log(opts, "[#{ts()}] #{model} · probe · #{probe_short(r)}")
            notify(opts, {:notify, {model, :probe, r}})
            {model, r}
        end,
        max_concurrency: max(1, parallel),
        timeout: stream_timeout,
        ordered: true,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    if unload? do
      Enum.each(models, fn m ->
        log(opts, "[#{ts()}] #{m} · unload · POST /api/chat keep_alive=0")
        notify(opts, {:notify, {m, :unload, :started}})
        u = Control.unload(m, verbose: verbose?)
        log(opts, "[#{ts()}] #{m} · unload · #{unload_short(u)}")
        notify(opts, {:notify, {m, :unload, unload_notify(u)}})
      end)
    end

    Enum.map(rows, fn
      {:ok, {m, r}} -> {m, r}
      {:exit, reason} -> {"_", {:error, {:stream_exit, reason}}}
    end)
  end

  def probe_with_retries(model, max_attempts, runner_opts) do
    probe_with_retries(model, 1, max_attempts, 250, runner_opts)
  end

  defp probe_with_retries(model, attempt, max_attempts, base_ms, runner_opts) do
    verbose? = Keyword.get(runner_opts, :verbose, false)

    if verbose? and attempt > 1 do
      IO.puts(:stderr, "[verify] retry attempt #{attempt}/#{max_attempts} model=#{model}")
    end

    case IntegrationVerify.probe(model, probe_invoke_opts(runner_opts)) do
      {:ok, _, _} = ok ->
        ok

      {:error, e} ->
        cond do
          attempt < max_attempts and retryable?(e) ->
            sleep = round(base_ms * :math.pow(2, attempt - 1))
            Process.sleep(min(sleep, 10_000))
            probe_with_retries(model, attempt + 1, max_attempts, base_ms, runner_opts)

          true ->
            {:error, e}
        end
    end
  end

  defp retryable?({:http, status, _}) when status in [429, 502, 503, 504], do: true

  defp retryable?(%Req.TransportError{reason: r})
       when r in [:timeout, :econnrefused, :closed, :enetunreach, :ehostunreach, :nxdomain],
       do: true

  defp retryable?(e) when is_exception(e) do
    msg = Exception.message(e)
    msg =~ "timeout" or msg =~ "closed" or msg =~ "econnrefused"
  end

  defp retryable?(_), do: false
end
