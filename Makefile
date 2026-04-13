# Optional smoke checks against a running Docker Compose stack (host has bash + Engine).
.PHONY: smoke-closed-egress check-dirteel-catalog test-dirteel help

help:
	@echo "Targets:"
	@echo "  smoke-closed-egress   Run scripts/verify-closed-agent-egress.sh (requires: docker compose up from repo root)"
	@echo "  check-dirteel-catalog  agents/dirteel/profiles vs Catalog (docker compose profile test + db)"
	@echo "  test-dirteel          Zig unit tests for agents/dirteel (requires: zig on PATH, e.g. 0.13.x)"

smoke-closed-egress:
	@chmod +x scripts/verify-closed-agent-egress.sh 2>/dev/null || true
	./scripts/verify-closed-agent-egress.sh

# Drift guard: closed_images.json must match Elixir ClosedAgents.Catalog.
check-dirteel-catalog:
	docker compose --profile test up -d db
	docker compose --profile test run --rm --entrypoint mix companion_test test test/companion/closed_agents/catalog_dirteel_sync_test.exs

test-dirteel:
	cd agents/dirteel && zig build test
