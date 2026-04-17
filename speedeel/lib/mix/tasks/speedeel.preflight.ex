defmodule Mix.Tasks.Speedeel.Preflight do
  @moduledoc """
  Runs the same checks Docker runs before `mix phx.server`: compile, npm install in `assets/`,
  asset build (Tailwind + esbuild), then **ExUnit in `MIX_ENV=test`** in a subprocess so Mix
  env rules are satisfied while Esbuild stays a `:dev`-only dependency.
  """
  use Mix.Task

  @shortdoc "Compile + npm + assets.build + mix test (test env in subprocess)"

  @impl Mix.Task
  def run(_) do
    Mix.Task.run("compile", [])
    Mix.Task.run("speedeel.npm", [])
    Mix.Task.run("assets.build", [])

    env =
      System.get_env()
      |> Map.put("MIX_ENV", "test")
      |> Map.to_list()

    {out, status} =
      System.cmd(
        "mix",
        ["test"],
        cd: File.cwd!(),
        env: env,
        stderr_to_stdout: true
      )

    Mix.shell().info(String.trim_trailing(out))

    if status != 0 do
      Mix.raise("mix test failed with exit #{status}")
    end
  end
end
