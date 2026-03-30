defmodule Companion.LabImageBuilder do
  @moduledoc false

  @topic "lab:image_build"

  def topic, do: @topic

  @doc """
  Build a lab image from a local Dockerfile context (must be mounted in the container).
  Runs `docker build` via System.cmd and streams lines over PubSub.
  Returns :ok | {:error, reason}.
  """
  def build(catalog_entry) do
    ctx = catalog_entry.build_context
    tag = catalog_entry.ref

    broadcast_line("Building #{tag} from #{ctx}…")

    case System.cmd("docker", ["build", "-t", tag, ctx],
           stderr_to_stdout: true,
           into: IO.stream()
         ) do
      {_output, 0} ->
        broadcast_line("Build succeeded: #{tag}")
        broadcast_done(:ok)
        :ok

      {_output, code} ->
        broadcast_line("Build failed (exit #{code})")
        broadcast_done({:error, {:build_failed, code}})
        {:error, {:build_failed, code}}
    end
  rescue
    e ->
      msg = Exception.message(e)
      broadcast_line("Build error: #{msg}")
      broadcast_done({:error, msg})
      {:error, msg}
  end

  @doc """
  Build asynchronously — spawns a Task so the caller returns immediately.
  """
  def build_async(catalog_entry) do
    Task.start(fn -> build(catalog_entry) end)
  end

  defp broadcast_line(text) do
    ts = DateTime.utc_now() |> DateTime.truncate(:second)

    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      @topic,
      {:lab_image_build, {:line, ts, text}}
    )
  end

  defp broadcast_done(result) do
    Phoenix.PubSub.broadcast(
      Companion.PubSub,
      @topic,
      {:lab_image_build, {:done, result}}
    )
  end
end
