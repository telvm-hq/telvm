defmodule Mix.Tasks.Speedeel.Npm do
  @moduledoc "Runs `npm install` in `assets/` for speedeel JS dependencies (e.g. three)."
  use Mix.Task

  @shortdoc "npm install in speedeel/assets"

  @impl Mix.Task
  def run(_) do
    assets = Path.join(File.cwd!(), "assets")

    unless File.dir?(assets) do
      Mix.raise("Expected assets/ at #{assets}")
    end

    unless File.exists?(Path.join(assets, "package.json")) do
      Mix.raise("Missing assets/package.json")
    end

    # On Windows, spawning `npm.cmd` directly can raise :eacces from open_port; `cmd /c` avoids it.
    {cmd, args} =
      case :os.type() do
        {:win32, _} -> {"cmd", ["/c", "npm", "install"]}
        _ -> {"npm", ["install"]}
      end

    {out, status} = System.cmd(cmd, args, cd: assets, stderr_to_stdout: true)

    if status != 0 do
      Mix.shell().error(out)
      Mix.raise("npm install failed with exit #{status}")
    end

    Mix.shell().info(String.trim_trailing(out))
  end
end
