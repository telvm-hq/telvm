# Changelog

All notable changes to this project are documented here and in [GitHub Releases](https://github.com/telvm-hq/telvm/releases).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html) where it applies to tagged releases.

## [0.1.0] — 2026-03-29

Initial public OSS snapshot. Summary: [`docs/releases/v0.1.0.md`](docs/releases/v0.1.0.md). HTTP automation surface: [`docs/agent-api.md`](docs/agent-api.md).

### Elixir / OTP and transport

- **Finch + Unix socket:** Docker Engine access uses **Finch** with a dedicated **`{:http, {:local, /var/run/docker.sock}}`** pool (**HTTP/1**), alongside the default pool used for **ProxyPlug** upstreams to containers on the bridge ([`application.ex`](companion/lib/companion/application.ex)).
- **Supervision:** top-level **`Companion.Supervisor`** is **`:rest_for_one`**; VM manager pre-flight runners start under a **`DynamicSupervisor`** on demand.
- **Real-time fan-out:** **Phoenix PubSub** feeds **LiveView** and the **`/telvm/api/stream`** SSE loop ([`docs/plumbing.md`](docs/plumbing.md)).

Docs: [Architecture — OTP, Finch, Docker socket](ARCHITECTURE.md#otp-finch-and-the-docker-unix-socket), [Why Elixir / OTP](ARCHITECTURE.md#why-elixir--otp), [Plumbing](docs/plumbing.md).

[0.1.0]: https://github.com/telvm-hq/telvm/releases/tag/v0.1.0
