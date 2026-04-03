# feat(ui): Warm assets logs preview, theme toggle, bone-white light mode

## Summary

Operator-facing companion changes: **Warm assets** preview column supports **container logs** (one-shot fetch, refresh, connection preamble with container id + timestamp), alongside existing port iframe and Explorer **files** embed. Row actions include polished lifecycle buttons (pause/restart vs resume/destroy) and a **logs** control.

**Theme:** Removes the three-way “system” (monitor) control in favor of explicit **light / dark**; default theme on first visit is **light**. Lightens DaisyUI light base tokens and telvm shell variables for a bone-adjacent light mode.

**Docs:** [`README.md`](README.md) and [`companion/README.md`](companion/README.md) describe the **Verify → Warm assets** loop and header theme.

## Depends on

This branch is stacked on **`feat/docker-container-logs-api`** (Docker `container_logs/2`, `GET /telvm/api/machines/:id/logs`, `fyi.md`). On GitHub:

- Open a PR for **`feat/docker-container-logs-api` → `main`** first ([`PR_BODY_docker_container_logs_api.md`](PR_BODY_docker_container_logs_api.md)).
- Then open **`feat/warm-assets-ui-theme` → `main`** after rebasing onto updated `main`, **or** temporarily target the API branch.

## User-visible

- `/warm`: logs panel, refresh, preamble lines; theme toggle (sun/moon only); lighter light-mode panels and toggle track.
- README: core loop (BYOI → Verify → Warm assets with previews, files, logs).

## Technical

- [`companion/lib/companion_web/live/status_live.ex`](companion/lib/companion_web/live/status_live.ex)
- [`companion/lib/companion_web/components/core_components.ex`](companion/lib/companion_web/components/core_components.ex)
- [`companion/lib/companion_web/live/explorer_live.ex`](companion/lib/companion_web/live/explorer_live.ex)
- [`companion/assets/css/app.css`](companion/assets/css/app.css), [`layouts.ex`](companion/lib/companion_web/components/layouts.ex), [`root.html.heex`](companion/lib/companion_web/components/layouts/root.html.heex)
- [`README.md`](README.md), [`companion/README.md`](companion/README.md)
- [`companion/test/companion_web/live/status_live_test.exs`](companion/test/companion_web/live/status_live_test.exs)

## How to test

- Load `/warm` and `/machines` in light and dark; open **logs** on a lab container; **refresh**; switch **files** / port preview and confirm logs state clears as designed.
- `localStorage["phx:theme"]` is `"light"` or `"dark"` only.

## Risk

Users who relied on **system** theme will get **light** until they choose **dark**.
