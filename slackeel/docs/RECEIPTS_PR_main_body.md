### Summary

Adds a **Receipts** LiveView at **`/receipts`** with ten **link-only** rows from Slack’s public **`slackapi/node-slack-sdk`** and **`slackapi/python-slack-sdk`** issue trackers (five each): GitHub links, **opened** dates (snapshot at curation), **open/closed** badges, and short **Slackeel contrast** lines. Large viewports use a **two-column** layout; title and theme stack in one cell for readability.

Also adds **nav** entry (Models → Receipts → Pre-Flight), **horizontal scroll** on the nav cluster when the Pre-flight strip is wide, **tests**, and **docs** for a suggested PR **follow-up comment** ([`RECEIPTS_PR_FOLLOWUP.md`](slackeel/docs/RECEIPTS_PR_FOLLOWUP.md), body file for `gh pr comment`).

### How to verify

1. `cd slackeel/server` → `mix phx.server` → open `http://127.0.0.1:4020/receipts`.
2. Confirm **Receipts** in the top nav and side-by-side panels from the **`lg`** breakpoint.
3. `mix test` under `slackeel/server`.

### Notes

- No Slack API calls or GitHub scraping; static curation only. Open/closed and titles can drift on GitHub over time.
