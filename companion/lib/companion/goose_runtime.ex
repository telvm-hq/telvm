defmodule Companion.GooseRuntime do
  @moduledoc false

  # Must match `images/goose/Dockerfile` install path; Engine exec has no shell PATH like `docker exec -it`.
  @goose_bin "/usr/local/bin/goose"

  @goose_label_filter %{"label" => ["telvm.goose=true"]}

  @doc "Absolute path to the Goose CLI inside the official telvm goose image."
  @spec goose_bin() :: String.t()
  def goose_bin, do: @goose_bin

  @doc """
  Returns the first Engine container with label `telvm.goose=true`, or `{:error, :not_found}`.
  """
  @spec find_container() :: {:ok, String.t(), String.t()} | {:error, :not_found | term()}
  def find_container do
    docker = Companion.Docker.impl()

    case docker.container_list(filters: @goose_label_filter) do
      {:ok, []} ->
        {:error, :not_found}

      {:ok, [first | _]} when is_map(first) ->
        id = first["Id"]

        if is_binary(id) do
          {:ok, id, summarize_state(first)}
        else
          {:error, :not_found}
        end

      {:ok, _} ->
        {:error, :not_found}

      {:error, _} = e ->
        e
    end
  end

  @doc """
  Tail container logs (stdout+stderr) for the Goose service container.
  """
  @spec logs(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def logs(container_id, opts \\ []) when is_binary(container_id) do
    tail = Keyword.get(opts, :tail, 200)
    Companion.Docker.impl().container_logs(container_id, tail: tail)
  end

  @doc """
  Restart the Goose container via the Engine API (same pattern as warm machine restart).
  """
  @spec restart_container(String.t()) :: :ok | {:error, term()}
  def restart_container(container_id) when is_binary(container_id) do
    Companion.Docker.impl().container_restart(container_id, timeout_sec: 10)
  end

  @doc """
  Runs a non-interactive Goose turn inside the container (`goose run --text …`).
  Used by the Agent tab so the UI can chat without exposing Docker commands.
  """
  @spec run_text(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def run_text(container_id, prompt)
      when is_binary(container_id) and is_binary(prompt) do
    trimmed = String.trim(prompt)

    if trimmed == "" do
      {:error, "Message is empty."}
    else
      cmd = [@goose_bin, "run", "--text", trimmed]

      case Companion.Docker.impl().container_exec_with_exit(container_id, cmd, []) do
        {:ok, %{stdout: out, exit_code: 0}} ->
          out = String.trim(to_string(out))
          {:ok, if(out == "", do: "(No text returned.)", else: out)}

        {:ok, %{stdout: out, exit_code: 127}} ->
          hint = String.trim(to_string(out))

          base =
            "Goose CLI not found in this exec session (exit 127). The companion uses #{@goose_bin}; rebuild the goose image or ensure the binary exists."

          err =
            if(hint == "",
              do: base,
              else: base <> " " <> hint <> runtime_deps_hint(hint)
            )

          {:error, err}

        {:ok, %{stdout: out, exit_code: code}} ->
          hint = String.trim(to_string(out))
          msg = "The agent returned an error (code #{code})."

          err =
            if(hint == "",
              do: msg,
              else: msg <> " " <> hint <> runtime_deps_hint(hint)
            )

          {:error, err}

        {:error, reason} ->
          {:error, "Could not run the agent. #{inspect(reason)}"}
      end
    end
  end

  defp runtime_deps_hint(text) when is_binary(text) do
    t = String.downcase(text)

    if String.contains?(t, "libgomp") or
         String.contains?(t, "error while loading shared libraries") do
      " Rebuild the `goose` image with runtime libs (see docs/quickstart.md — e.g. libgomp1)."
    else
      ""
    end
  end

  defp summarize_state(%{"State" => state}) when is_binary(state), do: state
  defp summarize_state(%{"Status" => status}) when is_binary(status), do: status
  defp summarize_state(_), do: "unknown"
end
