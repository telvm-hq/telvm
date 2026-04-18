# Release and PR helper artifacts

This folder holds **maintainer-facing** copy: GitHub PR bodies (`PR_BODY_*.md` / `*_github.txt`), split-PR notes, and release note drafts (`v*.md`). It is **not** on the default operator path — new users should follow [../quickstart.md](../quickstart.md) and [../wiki/GROUND_TRUTH.md](../wiki/GROUND_TRUTH.md).

| File | Purpose |
|------|---------|
| [SPLIT_PRS_workflow.md](SPLIT_PRS_workflow.md) | How to sequence stacked PRs |
| [v0.1.0.md](v0.1.0.md), [v1.1.0.md](v1.1.0.md) | Release note drafts |
| `PR_BODY_*.md` | Paste or `gh pr create --body-file` sources |

Do not delete files here without checking in-repo references (e.g. [../closed-agent-upstream-submodule-policy.md](../closed-agent-upstream-submodule-policy.md) mentions `docs/releases`).
