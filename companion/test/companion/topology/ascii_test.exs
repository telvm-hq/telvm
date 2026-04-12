defmodule Companion.Topology.AsciiTest do
  use ExUnit.Case, async: true

  alias Companion.Topology.Ascii

  test "warm_blueprint includes stack context, API, and signals" do
    out =
      Ascii.warm_blueprint([], {:ok, []})

    assert out =~ "telvm_default"
    assert out =~ "/telvm/api"
    assert out =~ "docker.sock"
    assert out =~ "signals"
    assert out =~ "Resource is still in use"
  end

  test "warm_blueprint empty stack and warm rows show discovery hints" do
    out = Ascii.warm_blueprint([], {:ok, []})
    assert out =~ "com.docker.compose.project=telvm"
    assert out =~ "no warm rows yet"
  end

  test "warm_blueprint with lab machines chunks five per row" do
    machines =
      for i <- 1..6 do
        %{
          name: "lab-#{i}",
          status: "running",
          image: "img",
          ports: [3000 + i],
          internal_ports: [40_000 + i]
        }
      end

    out = Ascii.warm_blueprint(machines, {:ok, []})
    assert out =~ "lab-1"
    assert out =~ "lab-6"
    assert out =~ "▼"
  end

  test "warm_blueprint unavailable stack still renders" do
    out = Ascii.warm_blueprint([], {:error, :unavailable})
    assert out =~ "unavailable"
  end
end
