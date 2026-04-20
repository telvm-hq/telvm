### Follow-up: impact (how big is this, really?)

**Direct operational impact on Slack the company:** essentially **none**. We are not calling Slack APIs, not scraping their product, and not affecting their infra or revenue.

**Where this *does* land, if we are honest about depth:**

1. **Buyer and integrator psychology** — During “build vs buy vs self-host” reviews, engineers routinely open **public issue trackers**. A first-party page that links *only* to Slack’s own repos makes the **integration tax** visible without inventing facts. That nudges evaluation conversations; it does not by itself migrate workspaces.

2. **Narrative surface area** — Issues like **supply-chain posture**, **OAuth / install edge cases**, **Socket Mode / WebSocket reliability**, and **logging of secrets** are not theoretical; they are filed against Slack-maintained SDKs. Collating them next to Slackeel’s “localhost-first” story is **comparative positioning**, not a security claim about Slack’s product.

3. **Depth of “damage”** — At most, **marginal**: a slightly shorter path for a skeptical engineer to cite **primary sources** in an internal memo. Slack’s teams already triage these threads; we are not adding new bugs, only **curating links** Slackeel operators might care about.

So: **high clarity, low blast radius** — unless we pretend this is more than a static reading list, which we should not.

---

### Next libraries (`slackapi/*`) worth extending the same pattern

If we add another “Receipts” strip or rotate curations, these are the **next 3–4** repos that would round out the story (same rules: public issues, links only, periodic refresh):

| Priority | Repository | Why it matters next |
| -------- | ---------- | ------------------- |
| 1 | [`slackapi/bolt-js`](https://github.com/slackapi/bolt-js) | **App framework** most teams actually ship on in Node; Socket Mode + HTTP receiver issues are where day-to-day Slack *app* pain shows up (we deliberately skipped Bolt in v1 of Receipts to keep scope SDK-only). |
| 2 | [`slackapi/bolt-python`](https://github.com/slackapi/bolt-python) | **Parity** with Bolt-JS for Python shops; same class of events, OAuth, and adapter bugs, different issue stream. |
| 3 | [`slackapi/slack-github-action`](https://github.com/slackapi/slack-github-action) | **CI/CD** surface: teams wiring Slack into GitHub Actions hit different failure modes than SDK-only users—good “enterprise glue” receipts. |
| 4 | [`slackapi/java-slack-sdk`](https://github.com/slackapi/java-slack-sdk) | **JVM / enterprise** long tail; different runtime and dependency story from Node/Python, same platform API underneath. |

**Honorable mentions** (if we want a fifth later): [`slackapi/deno-slack-sdk`](https://github.com/slackapi/deno-slack-sdk) (Run on Slack / Deno path), or [`slackapi/hubot-slack`](https://github.com/slackapi/hubot-slack) for legacy bot ops—lower relevance for *Slackeel’s* Phoenix direction but still `slackapi` primary sources.

---

### Maintainer note

Happy to tighten wording if legal/comms prefers softer framing; the **substance** stays: **links to Slack’s own trackers**, snapshot dates, no live GitHub dependency in-app.
