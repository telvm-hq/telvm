defmodule Slackeel.Ollama.VerifyRunner do
  @moduledoc """
  CLI wrapper around `Slackeel.Ollama.VerifyPipeline` for `mix slackeel.verify_ollama`.
  """

  alias Slackeel.Ollama.{Config, VerifyPipeline}

  @doc """
  Parses argv, runs the pipeline, prints to stdout. Returns `:ok` if all succeeded, else `:error`.

  Options:
  - `--parallel N` — concurrent probe requests in **phased** mode (default: env / Application)
  - `--serial` — **one model at a time**: pull → probe → unload before the next model
  - `--retries N` — attempts per model including first (default 3)
  - `--manifest PATH` — override `manifest/models.json`
  - `--model NAME` — probe only this Ollama tag (skips manifest list; for deep troubleshooting)
  - `--verbose` — log request URL, timeouts, and full HTTP error bodies to stderr
  - `--json` — machine-readable summary on stdout
  - `--skip-pull` — do not run `POST /api/pull` before probes (weights must already exist)
  - `--skip-unload` — do not run unload (`keep_alive: 0`) after probes
  - `--pull-parallel N` — concurrent pulls in **phased** mode (default **1**)
  """
  def run(argv) when is_list(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [
          parallel: :integer,
          retries: :integer,
          json: :boolean,
          manifest: :string,
          model: :string,
          verbose: :boolean,
          skip_pull: :boolean,
          skip_unload: :boolean,
          pull_parallel: :integer,
          serial: :boolean
        ],
        aliases: [p: :parallel, j: :json, m: :manifest, v: :verbose]
      )

    parallel = Keyword.get(opts, :parallel) || Config.integration_verify_max_parallel()
    retries = Keyword.get(opts, :retries) || 3
    json? = Keyword.get(opts, :json, false)
    verbose? = Keyword.get(opts, :verbose, false)
    pull? = not Keyword.get(opts, :skip_pull, false)
    unload? = not Keyword.get(opts, :skip_unload, false)
    pull_parallel = Keyword.get(opts, :pull_parallel) || 1
    serial? = Keyword.get(opts, :serial, false)

    manifest_path =
      Keyword.get(opts, :manifest) ||
        Application.get_env(:slackeel, :manifest_path) ||
        Path.expand("../../manifest/models.json", File.cwd!())

    models =
      case Keyword.get(opts, :model) do
        s when is_binary(s) and s != "" ->
          [String.trim(s)]

        _ ->
          load_models!(manifest_path)
      end

    mode = if serial?, do: :serial, else: :phased

    IO.puts(
      :stderr,
      "slackeel.verify_ollama: #{length(models)} model(s), mode=#{mode}, parallel=#{parallel}, retries=#{retries}"
    )

    IO.puts(:stderr, "  pull: #{if pull?, do: "yes (parallel=#{pull_parallel})", else: "no"}")
    IO.puts(:stderr, "  unload: #{if unload?, do: "yes", else: "no"}")

    case Keyword.get(opts, :model) do
      s when is_binary(s) and s != "" ->
        IO.puts(:stderr, "  mode: single model #{inspect(String.trim(s))}")

      _ ->
        IO.puts(:stderr, "  manifest: #{manifest_path}")
    end

    Process.delete(:slackeel_verify_probe_header)
    Process.delete(:slackeel_verify_unload_header)

    mix_log = fn
      {:notify, {:log, line}} ->
        IO.puts(:stderr, line)

      {:notify, inner} ->
        mix_stderr_log(mode, inner)
    end

    pipeline_opts = [
      mode: mode,
      pull: pull?,
      unload: unload?,
      retries: retries,
      verbose: verbose?,
      pull_parallel: pull_parallel,
      probe_parallel: parallel,
      on_event: mix_log
    ]

    if mode == :phased do
      IO.puts(:stderr, "Phase: pull")
    else
      IO.puts(:stderr, "Phase: serial (pull → probe → unload per model)")
    end

    results = VerifyPipeline.run(models, pipeline_opts)

    ok? = Enum.all?(results, fn {_, r} -> match?({:ok, _, _}, r) end)

    if json? do
      IO.puts(Jason.encode!(%{ok: ok?, results: format_json_results(results)}, pretty: true))
    else
      for {m, r} <- results do
        case r do
          {:ok, text, meta} ->
            preview = text |> String.slice(0, 200) |> String.replace("\n", " ")
            tps = meta[:tokens_per_sec]
            sfx = if tps, do: " · #{tps} tok/s", else: ""
            IO.puts("OK   #{m}#{sfx} — #{preview}")

          {:error, {:pull, _}} ->
            IO.puts("FAIL #{m} — pull failed (see stderr above)")

          {:error, e} ->
            IO.puts("FAIL #{m} — #{format_err(e)}")
        end
      end
    end

    if ok?, do: :ok, else: :error
  end

  defp mix_stderr_log(:phased, {_model, :pull, :started}), do: :ok
  defp mix_stderr_log(:phased, {model, :pull, :ok}), do: IO.puts(:stderr, "  pull OK   #{model}")

  defp mix_stderr_log(:phased, {model, :pull, {:error, e}}),
    do: IO.puts(:stderr, "  pull FAIL #{model} — #{format_err(e)}")

  defp mix_stderr_log(:phased, {_m, :probe, :started}), do: IO.puts(:stderr, "Phase: probe")
  defp mix_stderr_log(:phased, {_model, :probe, {:ok, _, _}}), do: :ok
  defp mix_stderr_log(:phased, {_model, :probe, {:error, _}}), do: :ok
  defp mix_stderr_log(:phased, {_model, :probe, r}) when is_tuple(r), do: :ok

  defp mix_stderr_log(:phased, {m, :unload, :started}), do: IO.puts(:stderr, "  unload → #{m}")
  defp mix_stderr_log(:phased, {_m, :unload, :ok}), do: :ok

  defp mix_stderr_log(:phased, {_m, :unload, {:error, e}}),
    do: IO.puts(:stderr, "  unload WARN — #{format_err(e)}")

  defp mix_stderr_log(:phased, {_m, :unload, other}),
    do: IO.puts(:stderr, "  unload note — #{inspect(other)}")

  defp mix_stderr_log(:serial, {model, :pull, :ok}), do: IO.puts(:stderr, "  pull OK   #{model}")

  defp mix_stderr_log(:serial, {model, :pull, {:error, e}}),
    do: IO.puts(:stderr, "  pull FAIL #{model} — #{format_err(e)}")

  defp mix_stderr_log(:serial, {_model, :probe, {:ok, text, meta}}) do
    prev = text |> String.replace("\n", " ") |> String.slice(0, 120)
    tps = meta[:tokens_per_sec]
    sfx = if tps, do: " · #{tps} tok/s", else: ""
    IO.puts(:stderr, "  probe OK#{sfx}  (preview) #{prev}")
  end

  defp mix_stderr_log(:serial, {model, :probe, {:error, e}}),
    do: IO.puts(:stderr, "  probe FAIL #{model} — #{format_err(e)}")

  defp mix_stderr_log(:serial, {_m, :cycle, _}), do: :ok
  defp mix_stderr_log(:serial, {_m, :unload, _}), do: :ok
  defp mix_stderr_log(_, _), do: :ok

  defp format_json_results(results) do
    Enum.map(results, fn {m, r} ->
      case r do
        {:ok, text, meta} -> %{model: m, status: "ok", reply: text, metrics: meta}
        {:error, e} -> %{model: m, status: "error", error: format_err(e)}
      end
    end)
  end

  defp load_models!(path) do
    case File.read(path) do
      {:ok, bin} ->
        case Jason.decode(bin) do
          {:ok, %{"models" => list}} when is_list(list) ->
            list
            |> Enum.map(& &1["ollama"])
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()

          _ ->
            IO.puts(:stderr, "Invalid manifest JSON: #{path}")
            System.halt(2)
        end

      {:error, _} ->
        IO.puts(:stderr, "Cannot read manifest: #{path}")
        System.halt(2)
    end
  end

  defp format_err({:pull, e}), do: "pull #{format_err(e)}"
  defp format_err({:http, s, b}), do: "HTTP #{s} #{inspect(b, limit: 120)}"
  defp format_err({:api, e}), do: "API #{inspect(e, limit: 120)}"
  defp format_err({:pull_response, o}), do: "pull unexpected #{inspect(o, limit: 120)}"
  defp format_err({:bad_shape, m}), do: "bad_shape #{inspect(m, limit: 80)}"
  defp format_err({:stream_exit, r}), do: "stream #{inspect(r, limit: 80)}"
  defp format_err(e) when is_binary(e), do: e
  defp format_err(e), do: inspect(e, limit: 200)
end
