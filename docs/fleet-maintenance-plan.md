# Bounded fleet maintenance implementation

Scope: harden Portless and T3 Node installers, add a read-only fleet auditor, and exercise isolated routing compatibility. No live upgrades, service restarts, DNS changes, app termination, or ownership changes. Work in this worktree only; do not commit or push without approval.

1. Make installer default invocation genuinely read-only. Fail closed before mutation for active work or uncertain ownership. Preserve previous configuration/runtime, restart only with explicit authorization, check HTTP readiness, and restore on failed activation. Test with mocked commands and temporary homes, never real service apply.
2. Build a standard-library Python audit CLI with bounded SSH/HTTP probes, explicit host and OS identity, distinct unknown/error outcomes, version and executable ownership, secret-safe structured output, and timestamped local reports. Test classification and timeouts. Run a real read-only fleet audit.
3. Build isolated routing compatibility tests using disposable state, high loopback ports and unique fixture directories. Test HTTP, WebSocket, static routing, normal/abrupt cleanup and worktree/framework behavior where supported. Do not claim mocked evidence as live compatibility. Preserve real development services.
4. Run tests/lint, DiffWarden iterative review until no valid findings remain, and verify final diff. Document actual results, gaps, and deployment deferrals. Compare live service/config snapshots after the fixtures to detect unintended production changes.

See [fleet-maintenance-boundaries.md](fleet-maintenance-boundaries.md) for evidence limits and unchanged Caddy/migration-script risks. The existing version pins remain untouched. No inferred permission to activate any candidate follows from passing tests.
