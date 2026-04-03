defmodule TelvmLab.MixProject do
  use Mix.Project

  def project do
    [
      app: :telvm_lab,
      version: "0.1.0",
      elixir: "~> 1.14",
      deps: deps(),
      releases: [
        telvm_lab: [
          include_executables_for: [:unix],
          applications: [runtime_tools: :permanent]
        ]
      ]
    ]
  end

  def application do
    [extra_applications: [:logger], mod: {TelvmLab.Application, []}]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7.0"},
      {:bandit, "~> 1.0"},
      {:jason, "~> 1.4"}
    ]
  end
end
