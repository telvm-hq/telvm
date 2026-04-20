defmodule SlackeelWeb.ReceiptsLive do
  @moduledoc """
  Curated **primary sources**: recent high-signal threads on Slack’s public **Node** and **Python** SDK repos.
  Each row links to the canonical GitHub issue; titles match issue titles at curation time (open/closed badges may drift).

  **`opened_on`** values are the GitHub **Created** dates at curation time (not fetched live).
  """
  use SlackeelWeb, :live_view

  @doc """
  Five recent `slackapi/node-slack-sdk` issues (semver, supply chain, API shape, DX, i18n headers).
  States verified against GitHub on 2026-04-20 (US) — refresh if badges look stale.
  """
  def node_slack_sdk_receipts do
    [
      %{
        repo: "slackapi/node-slack-sdk",
        number: 2359,
        opened_on: ~D[2025-09-04],
        title: "Removing support for Node 18 and other upcoming breaking changes",
        url: "https://github.com/slackapi/node-slack-sdk/issues/2359",
        theme: "Semver / runtime churn",
        state: :open,
        contrast:
          "Your Phoenix release runs on **your** Erlang/OTP pin—no pinned mega-thread of coordinated breaking releases from a vendor monorepo."
      },
      %{
        repo: "slackapi/node-slack-sdk",
        number: 2541,
        opened_on: ~D[2026-03-31],
        title: "Commit a lockfile to protect against supply chain attacks",
        url: "https://github.com/slackapi/node-slack-sdk/issues/2541",
        theme: "Supply chain / dev installs",
        state: :open,
        contrast:
          "Mix `mix.lock` + Hex is the default contract; Slackeel does not ask contributors to `npm install` an unpinned library graph to hack on chat."
      },
      %{
        repo: "slackapi/node-slack-sdk",
        number: 2550,
        opened_on: ~D[2025-12-28],
        title: "conversations.setTopic missing `channel.latest` in returned object",
        url: "https://github.com/slackapi/node-slack-sdk/issues/2550",
        theme: "Typed client vs API truth",
        state: :open,
        contrast:
          "When the payload is yours end-to-end, “undefined where docs promised a field” is a bug you fix in one codebase—not a distributed client/SDK drift surface."
      },
      %{
        repo: "slackapi/node-slack-sdk",
        number: 2468,
        opened_on: ~D[2026-01-13],
        title:
          "Introduce search functionality in slack conversations.list & users.list method by name or any other method to search.",
        url: "https://github.com/slackapi/node-slack-sdk/issues/2468",
        theme: "List-at-scale DX",
        state: :open,
        contrast:
          "Postgres `ILIKE` / full-text / dedicated search indices on **your** data—no paging megabytes through `conversations.list` because the hosted API has no first-class search."
      },
      %{
        repo: "slackapi/node-slack-sdk",
        number: 2544,
        opened_on: ~D[2026-04-07],
        title: "When using in Windows-Japanese-Admin-powershell, App.run failed due to invalid User-Agent",
        url: "https://github.com/slackapi/node-slack-sdk/issues/2544",
        theme: "Instrumentation / i18n headers",
        state: :closed,
        contrast:
          "Default HTTP clients for Ollama/Finch do not embed localized `process.title` into mandatory headers—fewer “works in en_US, dies in ja_JP admin shell” surprises."
      }
    ]
  end

  @doc """
  Five recent `slackapi/python-slack-sdk` issues (security logging, uploads, webhooks, OAuth, release regression).
  """
  def python_slack_sdk_receipts do
    [
      %{
        repo: "slackapi/python-slack-sdk",
        number: 1826,
        opened_on: ~D[2026-01-30],
        title: "Proxy URL log can expose proxy credentials",
        url: "https://github.com/slackapi/python-slack-sdk/issues/1826",
        theme: "Security / DEBUG logging",
        state: :open,
        contrast:
          "Proxy and secrets policy for `Req`/`Finch` stays in **your** `runtime.exs` and logging filters—not a third-party DEBUG line printing `bob:secret@`."
      },
      %{
        repo: "slackapi/python-slack-sdk",
        number: 1853,
        opened_on: ~D[2026-04-07],
        title: "files_upload_v2 should respect the retry handlers",
        url: "https://github.com/slackapi/python-slack-sdk/issues/1853",
        theme: "Multipart upload retries",
        state: :open,
        contrast:
          "File upload orchestration to your own storage (or a single well-owned HTTP pipeline) gets one supervised retry story—not step (2) bypassing the SDK’s retry graph."
      },
      %{
        repo: "slackapi/python-slack-sdk",
        number: 1847,
        opened_on: ~D[2026-03-30],
        title: "markdown block type not supported when sending via WebhookClient / response_url",
        url: "https://github.com/slackapi/python-slack-sdk/issues/1847",
        theme: "Webhook vs WebClient parity",
        state: :open,
        contrast:
          "Block payloads are rendered by **your** LiveView HEEx and HEEx rules—no “Block Kit works in `chat.postMessage` but 500s on `response_url`” split brain."
      },
      %{
        repo: "slackapi/python-slack-sdk",
        number: 1823,
        opened_on: ~D[2026-01-23],
        title: "Stateless OAuth State Store",
        url: "https://github.com/slackapi/python-slack-sdk/issues/1823",
        theme: "OAuth parity with Node SDK",
        state: :open,
        contrast:
          "Phoenix session + CSRF for first-party login is one stack; you are not chasing cross-language OAuth helper parity between Slack’s Node and Python kits."
      },
      %{
        repo: "slackapi/python-slack-sdk",
        number: 1832,
        opened_on: ~D[2026-02-14],
        title:
          "Upgrading to 3.40.0 causing token rotation and installation to fail due to installation.installed_at change.",
        url: "https://github.com/slackapi/python-slack-sdk/issues/1832",
        theme: "Point release / DB types",
        state: :closed,
        contrast:
          "Ecto migrations and `DateTime` awareness are explicit in **your** migrations—no surprise offset-naive vs offset-aware breakage from a dependency bump in someone else’s OAuth store."
      }
    ]
  end

  @doc false
  def all_receipts do
    node_slack_sdk_receipts() ++ python_slack_sdk_receipts()
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Receipts",
       top_bar_title: nil,
       snapshot: nil,
       show_ollama_hud: false,
       verify_running: false,
       node_receipts: node_slack_sdk_receipts(),
       python_receipts: python_slack_sdk_receipts()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="telvm-terminal telvm-console-shell slac-tactical slac-preflight-view flex min-h-0 flex-1 flex-col gap-3 px-3 py-3 sm:px-4 sm:py-4">
      <div class="shrink-0 space-y-2">
        <div class="flex flex-wrap items-baseline gap-x-3 gap-y-1 font-mono">
          <h1 class="text-xs font-semibold uppercase tracking-wide telvm-accent-text sm:text-sm">
            Receipts
          </h1>
          <span class="telvm-muted-xs text-[10px] tracking-tight">
            slackapi/node-slack-sdk · slackapi/python-slack-sdk
          </span>
        </div>
        <p class="max-w-4xl text-[11px] leading-relaxed text-[var(--telvm-shell-muted)] sm:text-xs">
          Ten <strong class="text-[var(--telvm-shell-fg)]">recent</strong> issues from Slack’s own Node and Python SDK repos (2025–2026): breaking upgrades, supply-chain posture,
          API/Webhook parity, OAuth gaps, and logging footguns. Bolt-JS is intentionally omitted here—this tab is SDK-only.
          Slackeel is not a Slack client; compare vendor integration tax to a localhost-first Phoenix stack (see the
          <a
            href="https://github.com/telvm-hq/telvm/blob/main/slackeel/README.md"
            target="_blank"
            rel="noopener noreferrer"
            class="telvm-accent-text underline decoration-dotted underline-offset-2 hover:opacity-90"
          >
            Slackeel README
          </a>
          in the Telvm monorepo). On wide screens the two SDKs are <strong class="text-[var(--telvm-shell-fg)]">side by side</strong>.
        </p>
      </div>

      <div
        id="receipts-sdk-grid"
        class="grid min-h-0 flex-1 grid-cols-1 gap-3 lg:grid-cols-2 lg:items-stretch lg:gap-3"
      >
        <.receipt_section
          title="Node — slackapi/node-slack-sdk"
          rows={@node_receipts}
          dom_id="receipts-node-sdk"
        />
        <.receipt_section
          title="Python — slackapi/python-slack-sdk"
          rows={@python_receipts}
          dom_id="receipts-python-sdk"
        />
      </div>

      <p class="text-[9px] leading-snug text-[var(--telvm-shell-muted)] sm:text-[10px]">
        Slack and related marks are trademarks of Slack Technologies, LLC. Issue titles are quoted from public GitHub threads;
        <strong class="text-[var(--telvm-shell-fg)]">Opened</strong> is the GitHub created date at curation time. Open/closed state may change after this build.
      </p>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :rows, :list, required: true
  attr :dom_id, :string, required: true

  defp receipt_section(assigns) do
    ~H"""
    <section
      id={@dom_id}
      class="slac-card telvm-verify-card telvm-panel-border flex h-full min-h-0 flex-col overflow-hidden border border-[color:var(--telvm-shell-border)] font-mono"
    >
      <div class="slac-card__hdr flex shrink-0 !py-1 flex-wrap items-center justify-between gap-2 text-[9px] font-semibold uppercase tracking-[0.12em] text-[var(--telvm-shell-muted)]">
        <span>{@title}</span>
        <span class="tabular-nums">{length(@rows)} threads</span>
      </div>
      <div class="slac-card__body flex min-h-[17rem] flex-1 flex-col overflow-auto !pt-1.5 lg:min-h-[20rem]">
        <table class="w-full min-w-0 table-fixed text-left text-[10px] sm:text-[11px]">
          <colgroup>
            <col class="w-[2.75rem]" />
            <col class="w-[5.25rem]" />
            <col class="min-w-0" />
            <col class="w-[3.5rem]" />
            <col class="w-[36%]" />
          </colgroup>
          <thead class="sticky top-0 z-[1] border-b border-[color:var(--telvm-shell-border)] bg-[color-mix(in_oklch,var(--telvm-shell-elevated)_88%,var(--telvm-shell-bg))]">
            <tr>
              <th class="whitespace-nowrap px-1.5 py-1 font-semibold sm:px-2 sm:py-1.5">#</th>
              <th class="whitespace-nowrap px-1.5 py-1 font-semibold sm:px-2 sm:py-1.5">Opened</th>
              <th class="px-1.5 py-1 text-left font-semibold sm:px-2 sm:py-1.5">
                <span class="block leading-tight">Title</span>
                <span class="mt-0.5 block text-[8px] font-normal normal-case tracking-normal text-[var(--telvm-shell-muted)]">
                  Theme
                </span>
              </th>
              <th class="whitespace-nowrap px-1.5 py-1 font-semibold sm:px-2 sm:py-1.5">State</th>
              <th class="px-1.5 py-1 font-semibold sm:px-2 sm:py-1.5">Slackeel contrast</th>
            </tr>
          </thead>
          <tbody>
            <tr
              :for={r <- @rows}
              class="border-b border-[color-mix(in_oklch,var(--telvm-shell-border)_55%,transparent)] align-top hover:bg-[color-mix(in_oklch,var(--telvm-shell-elevated)_35%,transparent)]"
            >
              <td class="whitespace-nowrap px-1.5 py-1.5 tabular-nums text-[var(--telvm-shell-muted)] sm:px-2 sm:py-2">
                {r.number}
              </td>
              <td class="whitespace-nowrap px-1.5 py-1.5 tabular-nums text-[var(--telvm-shell-muted)] sm:px-2 sm:py-2">
                {Calendar.strftime(r.opened_on, "%Y-%m-%d")}
              </td>
              <td class="min-w-0 px-1.5 py-2 sm:px-2 sm:py-2.5">
                <div class="flex min-w-0 flex-col gap-1.5">
                  <a
                    href={r.url}
                    target="_blank"
                    rel="noopener noreferrer"
                    class="telvm-accent-text block min-w-0 hyphens-auto break-words text-[10px] leading-snug underline decoration-dotted underline-offset-2 hover:opacity-90 sm:text-[11px] sm:leading-snug"
                    title={r.title}
                  >
                    {r.title}
                  </a>
                  <div
                    class="border-t border-[color-mix(in_oklch,var(--telvm-shell-border)_65%,transparent)] pt-1.5 text-[9px] leading-snug text-[var(--telvm-shell-muted)] sm:text-[10px]"
                    title={r.theme}
                  >
                    <span class="block break-words font-medium text-[color-mix(in_oklch,var(--telvm-shell-fg)_82%,var(--telvm-shell-muted))]">
                      {r.theme}
                    </span>
                  </div>
                </div>
              </td>
              <td class="whitespace-nowrap px-1.5 py-1.5 align-top sm:px-2 sm:py-2">
                <span class={[
                  "inline-flex rounded-sm border px-1 py-0.5 text-[8px] font-bold uppercase tracking-wider sm:px-1.5 sm:text-[9px]",
                  receipt_state_class(r.state)
                ]}>
                  {receipt_state_label(r.state)}
                </span>
              </td>
              <td class="min-w-0 px-1.5 py-1.5 text-[9px] leading-snug text-[var(--telvm-shell-muted)] sm:px-2 sm:py-2 sm:text-[10px]">
                <span class="line-clamp-4 break-words">{r.contrast}</span>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>
    """
  end

  defp receipt_state_label(:open), do: "open"
  defp receipt_state_label(:closed), do: "closed"

  defp receipt_state_class(:open) do
    "border-[color-mix(in_oklch,var(--telvm-accent)_50%,transparent)] text-[var(--telvm-accent)]"
  end

  defp receipt_state_class(:closed) do
    "border-[color:var(--telvm-shell-border)] text-[var(--telvm-shell-muted)]"
  end
end
