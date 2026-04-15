# Pull request draft (copy into GitHub or use `gh`)

**Suggested title:** `docs: SF Frontier celiac dinner pack + Tuesday Apr 28, 2026 schedule`

Open from the CLI after pushing branch `docs/sf-frontier-celiac-dinner-schedule` (or your branch name):

```bash
gh pr create --base main --title "docs: SF Frontier celiac dinner pack + Tuesday Apr 28, 2026 schedule" --body-file docs/releases/PR_BODY_sf_frontier_celiac_dinners_github.txt
```

**Body** (same text as `PR_BODY_sf_frontier_celiac_dinners_github.txt`):

---

## Summary

Adds and updates operational documentation for the **nine-session**, **30-guest**, strict **gluten-free** carnivore/keto dinner series at **Frontier Tower, San Francisco** (Luma), including a fixed **weekly Tuesday** calendar with **Session 1 on Tuesday, April 28, 2026**.

## What changed

- **`docs/events/sf-frontier-celiac-dinners/`** — venue checklist, beverage policy (wine math + certified GF beer), counsel-review Luma/on-site copy drafts, full **menu-pack** with oven-pull template, manufacturing comms arc + go/no-go rubric, and **README** index.
- **`docs/events/sf-frontier-celiac-dinners/schedule.md`** (new) — nine Tuesday dates (**Apr 28 → Jun 23, 2026**) mapped to menu themes.
- Cross-links and copy updates in **README**, **venue-spec**, **menu-pack**, **manufacturing-comms-arc**, and **legal-copy** so the **Apr 28, 2026** start is consistent.
- **`docs/releases/PR_BODY_sf_frontier_celiac_dinners.md`** and **`PR_BODY_sf_frontier_celiac_dinners_github.txt`** — PR description for `gh pr create --body-file` and phone review.

## Not in scope

- No application or CI behavior changes.
- Plan file under `.cursor/plans/` is **not** modified per organizer request.

## How to approve from your phone

1. Open the PR in the GitHub app once it exists.
2. Read **Summary** + **What changed** above (or the **Files changed** tab).
3. Tap **Review** → **Approve**, then **Merge** when green (if you use merge queues, follow your team rule).

## Testing

- Documentation only; no tests required.
