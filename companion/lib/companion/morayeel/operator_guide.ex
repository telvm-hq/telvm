defmodule Companion.Morayeel.OperatorGuide do
  @moduledoc false

  @playwright_intro "https://playwright.dev/docs/intro"

  @doc "Static copy for the Morayeel LiveView runbook (cluster vs local, install, commands)."
  def data do
    %{
      playwright_intro_url: @playwright_intro,
      verification_doc: "docs/morayeel-verification.md",
      additions_doc: "agents/morayeel/morayeel_additions.md",
      readme_path: "agents/morayeel/README.md",
      comparison_rows: comparison_rows(),
      docker_smoke_snippet: docker_smoke_snippet(),
      docker_session_hint: docker_session_hint(),
      install_os_blocks: install_os_blocks(),
      local_headless_snippet: local_headless_snippet(),
      local_headed_snippet: local_headed_snippet(),
      when_to_use: when_to_use_paragraph()
    }
  end

  defp comparison_rows do
    [
      %{
        topic: "Who runs Playwright",
        in_docker: "Companion MorayeelRunner: docker run morayeel image on telvm_default.",
        locally: "You run node (or scripts/morayeel-run) on your laptop shell."
      },
      %{
        topic: "Display / UI",
        in_docker:
          "Default image: headless only. Session mode uses CDP on a published port for attach.",
        locally:
          "Headless by default; MORAYEEL_HEADLESS=0 or --headed opens a real browser window."
      },
      %{
        topic: "Network & DNS",
        in_docker:
          "Compose service names (e.g. morayeel_lab, companion) resolve on the bridge network.",
        locally:
          "localhost and your host resolver; morayeel_lab is not defined unless you map hosts or use real URLs."
      },
      %{
        topic: "Egress / proxy",
        in_docker:
          "HTTP_PROXY to companion:4003 with NO_PROXY for morayeel_lab (lab direct, other traffic via allowlist).",
        locally: "Unset unless you configure a proxy; traffic follows your host routes and VPN."
      },
      %{
        topic: "TLS / trust store",
        in_docker: "Playwright base image CA bundle inside the container.",
        locally: "Host OS trust store and any corporate MITM certs you installed."
      },
      %{
        topic: "Artifacts location",
        in_docker:
          "morayeel_runs volume under /artifacts/<run_id>/ (served by companion when mounted).",
        locally:
          "OUT_DIR you set (e.g. /tmp/morayeel-out); not wired to LiveView links unless you copy files."
      },
      %{
        topic: "CI",
        in_docker: "mix test / companion_test runs headless Docker path only.",
        locally: "Optional; not invoked by the LiveView button."
      }
    ]
  end

  defp docker_smoke_snippet do
    ~S"""
    docker compose run --rm \
      --network telvm_default \
      -v morayeel_runs:/artifacts \
      -e TARGET_URL=http://morayeel_lab:8080/ \
      -e OUT_DIR=/artifacts/smoke-manual \
      -e HTTP_PROXY=http://companion:4003 \
      -e HTTPS_PROXY=http://companion:4003 \
      -e NO_PROXY=companion,db,ollama,localhost,127.0.0.1,morayeel_lab \
      morayeel:latest
    """
    |> String.trim()
  end

  defp docker_session_hint do
    "For MORAYEEL_CAPTURE=session, publish CDP (e.g. -p 9222:9222) and see agents/morayeel/README.md — Session mode."
  end

  defp install_os_blocks do
    common = ["cd agents/morayeel", "npm ci", "npx playwright install chromium"]

    [
      %{
        os: "Windows (cmd/PowerShell)",
        lines: common ++ ["# OS deps: https://playwright.dev/docs/intro"]
      },
      %{os: "macOS", lines: common ++ ["# OS deps: https://playwright.dev/docs/intro"]},
      %{
        os: "Linux",
        lines:
          common ++
            ["# Often needs: sudo npx playwright install-deps chromium (see upstream docs)"]
      }
    ]
  end

  defp local_headless_snippet do
    ~S"""
    # Default TARGET_URL is http://127.0.0.1:4000/ (companion) when unset — start companion first.
    export OUT_DIR="/tmp/morayeel-out"
    mkdir -p "$OUT_DIR"
    node run.mjs

    # Or an explicit site:
    # export TARGET_URL="https://example.com/"
    """
    |> String.trim()
  end

  defp local_headed_snippet do
    ~S"""
    export OUT_DIR="/tmp/morayeel-out"
    mkdir -p "$OUT_DIR"
    ./scripts/morayeel-run.sh --headed

    # PowerShell (from agents\morayeel) — same default URL when TARGET_URL unset:
    #   .\scripts\morayeel-run.ps1 -Headed
    """
    |> String.trim()
  end

  defp when_to_use_paragraph do
    "Classic WebForms-style apps may need a second XHR POST after the GET shell; see morayeel_additions.md. " <>
      "Use headed locally when you want to see the page; use MORAYEEL_CAPTURE=session plus CDP when you stay headless in Docker but drive the browser from the host."
  end
end
