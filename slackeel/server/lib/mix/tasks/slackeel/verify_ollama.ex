defmodule Mix.Tasks.Slackeel.VerifyOllama do
  use Mix.Task

  @shortdoc "Verify every manifest Ollama model (parallel, retries); exit 1 if any fail"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.config")

    # Do not bind an HTTP port for this one-shot check.
    Application.put_env(:slackeel, SlackeelWeb.Endpoint, server: false)

    Mix.Task.run("app.start")

    case Slackeel.Ollama.VerifyRunner.run(args) do
      :ok ->
        :ok

      :error ->
        exit({:shutdown, 1})
    end
  end
end
