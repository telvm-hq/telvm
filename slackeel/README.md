# Slackeel

Self-hostable team collaboration and **local inference** orchestration—documentation-first until the application lands in its own Phoenix umbrella.

## Status

**Phase:** documentation and model catalog only (no application code in-tree yet).

## Documents


| Doc                                            | Purpose                                                                               |
| ---------------------------------------------- | ------------------------------------------------------------------------------------- |
| [docs/MODEL_CATALOG.md](docs/MODEL_CATALOG.md) | **Ground truth:** five model families, planned Ollama ids, approximate disk use       |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)   | Conceptual architecture: separate Phoenix LiveView app, boundaries, relation to Telvm |


## Conventions

- **Disk figures** are **approximate** (Ollama blobs + quantization). Operators should confirm with `ollama show <name>` after pull.
- **Families** are a **governance** list (five); individual **tags** evolve with the Ollama library—update the catalog when pins change.

## Relationship to Telvm

Telvm’s [utilities-ollama.md](../docs/utilities-ollama.md) describes the **Ollama utility** (pinned image, smoke tests). Slackeel will **consume** the same OpenAI-compatible `/v1` contract; it does not fork Ollama.