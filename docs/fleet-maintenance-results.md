# Fleet maintenance implementation results

Point-in-time report generated 2026-09-05 02:58 UTC, September 4 in Denver. Re-run the auditor before relying on host status. This branch is not deployed.

## Delivered

- Read-only fleet inventory with bounded SSH and HTTP probes, host/OS checks, secret-safe JSON, and separate service, endpoint, and binary-selection evidence. Usage: [fleet-audit.md](fleet-audit.md).
- Hardened Portless and T3 Node maintenance helpers with zero-write defaults, explicit restart/idle authorization, ownership checks, staged candidate validation, configuration conflict detection, effective-command verification, and rollback. Usage and limitations: [fleet-installer-maintenance.md](fleet-installer-maintenance.md).
- Real isolated macOS and Linux routing fixtures. Details: [compat-portless-isolated.md](compat-portless-isolated.md) and [fleet-portless-compatibility.md](fleet-portless-compatibility.md).
- Corrected old pending-restart/version tasks and documented unchanged Caddy risks. See [fleet-maintenance-boundaries.md](fleet-maintenance-boundaries.md).

## Verified

45 unit tests passed with zero failures/errors. Python parsing, Bash syntax, ShellCheck warning-level checks, and `git diff --check` passed. Tests include simulated Linux and macOS activation failures and rollback. No actual service apply was executed.

Both real platform fixtures recorded 17 passes, one failure, and two deferred groups. HTTP, WebSocket echo, static aliases, normal/SIGTERM cleanup, linked-worktree Astro HTML, and HMR protocol passed. The failure is wrapper SIGKILL leaving a live backend and serving route. Fixture cleanup then removed its own processes, listeners, routes, and temporary directories. Do not close the abrupt-exit gate or assume a full application migration is accepted.

The auditor completed six matching Unix inventories. Luma timed out. Haste was reachable on Windows as `DESKTOP-4S98CUV`, so Linux inventory was correctly skipped. Haste's T3 endpoint returned HTTP 200 while its development ingress was unreachable. The other six hosts returned the expected Portless missing-route response through Caddy and T3 HTTP 200.

Before/after readback on Koopa, Metapod, Mander, Tortle, Saur, and Herb found no change in the captured service/configuration state, managed version selection, or T3 process/start evidence. This covers the sampled fields, not every file or process on the hosts.

## Review decisions

DiffWarden's configured default reviewer was used in strict full-diff passes. Accepted and fixed findings included:

- Verify the effective Node override after activation, not just HTTP readiness.
- Refuse configuration/runtime changes during staging rather than overwrite them.
- Update fake process inventories to exercise descendant-listener checks correctly.
- Bound WebSocket receives on EOF, response size, and total deadline so a failed peer cannot prevent cleanup.
- Contain malformed HTTP protocol responses within endpoint observations instead of losing the host inventory.

Regression tests cover these changes. No finding was declined. Review artifacts retain exact per-round verdicts and reviewer warnings; later rounds supersede earlier snapshots. The reviewer uses shared CODEX_HOME with an enforced read-only thread and denied approval escalation. That warning is not a deployment authorization.

## Evidence and remaining work

Local evidence root: `/Users/auro/workspace/fleet-maintenance-evidence/`.

- `verification.json`, `unit-tests.txt`
- `fleet-audit.json`
- `compat-macos-reviewed.json`, `compat-portless-saur-results.json`
- `compat-saur-cleanup.json`
- `fleet-live-state-before.json`, `fleet-live-state-after-verification.json`
- `review-round-*.json`

No version pins, installed packages, DNS, Tailscale settings, service enablement, desktop ownership, or authentication were changed. No live service restart, reboot, app quit, or fleet-wide apply occurred. Development/test files are confined to the separate worktree and owned temporary fixture/evidence locations.

Remaining gates are the real Portless abrupt-exit defect, production application/Webmux/browser acceptance, privileged Caddy adapter hardening, actual maintenance-window rollback/cutover and cold-boot tests, desktop updater policy, Codex executable ownership reconciliation, and separately approved T3 ownership/TLS/roaming decisions. Offline or wrong-OS hosts do not block local engineering and must never trigger automatic updates when they reappear.
