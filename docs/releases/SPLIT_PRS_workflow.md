# Split PR workflow (Docker API vs operator UI)

Branches created locally:

| Branch | Base | Commit | PR body |
|--------|------|--------|---------|
| `feat/docker-container-logs-api` | `main` | `4987969` (approx.) | [`PR_BODY_docker_container_logs_api.md`](PR_BODY_docker_container_logs_api.md) |
| `feat/warm-assets-ui-theme` | `feat/docker-container-logs-api` | `04951c6` (approx.) | [`PR_BODY_theme_light_surfaces.md`](PR_BODY_theme_light_surfaces.md) |

The integration branch **`fix/ci-warm-assets-test`** still contains the pre-split WIP commit (`57693aa`). You can delete it or reset it to match `feat/warm-assets-ui-theme` after the split PRs are merged.

## 1. Push and open PR1 (API)

```bash
git push -u origin feat/docker-container-logs-api
```

Open a pull request **into `main`** using the title and body from `docs/releases/PR_BODY_docker_container_logs_api.md`.

**Merge PR1** in GitHub after CI and review.

## 2. Rebase UI branch onto main (after PR1 merges)

```bash
git fetch origin main
git checkout feat/warm-assets-ui-theme
git rebase origin/main
# resolve conflicts if any
git push -u origin feat/warm-assets-ui-theme --force-with-lease
```

Open PR2 **into `main`** using `docs/releases/PR_BODY_theme_light_surfaces.md`.

Alternatively, before PR1 merges, open PR2 **into `feat/docker-container-logs-api`** for a stacked review; then rebase PR2 onto `main` once PR1 lands.

## 3. Optional: align `fix/ci-warm-assets-test`

After both PRs merge:

```bash
git checkout fix/ci-warm-assets-test
git reset --hard origin/main
```

Or delete the old branch if no longer needed.
