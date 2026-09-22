# Hardened service maintenance helpers

These helpers are implemented and tested in isolation. No live installation, update, restart, or ownership change was performed for their validation. Do not treat unit-test success as a real systemd/launchd cutover or rollback test.

## T3 native-runtime compatibility

T3 `0.0.42` ships a native runtime, not the older `node_modules/t3/dist/bin.mjs` layout. `install_t3_node_override.sh` and its transaction engine remain Node-specific. Do not use them on a native T3 deployment or recreate `service-node.conf`. The shared T3 pin remains `0.0.40` pending a reviewed native-aware installer; it is not the latest upstream release or the version on every host.

A host-specific native migration was verified on Herb on 2026-09-22. It backed up the service, drop-ins, settings and consistent SQLite state, removed only the exact obsolete stable-Node override, and used the verified native binary's supported `update 0.0.42 --base-dir <existing-home> --yes` command. The stock updater owns the main unit's native `__service-launcher` ExecStart. Network and unrelated unit settings were preserved. Executable identity, single listener, exact backend version, and a real T3-to-Codex request passed.

Do not treat a zero installer exit or HTTP homepage as acceptance. The old Node override can keep a newly selected native runtime from starting even when the deprecated updater reports success. Check T3's own active-work state and stop-propagation relationships before an authorized T3-only restart; do not stop games or unrelated agents to satisfy a conservative generic guard. Database migrations require explicit preservation checks, and service rollback alone does not prove arbitrary cross-schema database rollback is safe.

## Read-only default

```sh
bash dot_scripts/fleet_services/install_portless_service.sh
bash dot_scripts/fleet_services/install_t3_node_override.sh
```

Both print a plan without checking the host, creating directories, downloading packages, or changing services. Use the fleet auditor for actual inventory. Python launchers use `-B` so bytecode cache creation does not violate the zero-write default.

## Explicit maintenance authorization

A future maintenance window must explicitly authorize all three flags:

```text
--apply --allow-restart --confirm-idle
```

These flags are not authorized by this implementation pass. `--confirm-idle` is an operator assertion covering agent sessions, terminals, and competing desktop ownership that a process inventory cannot prove safe. It does not override detected work or uncertain ownership. The process veto is conservative and may block maintenance when an unrelated coding agent is running.

The helpers preserve existing service enablement and do not enable lingering, change system-service ownership, or add a second T3 backend. A newly started service is not thereby enabled for boot/login persistence. They are not a general host-bootstrap installer.

## Promotion and recovery

- Verify the expected service fragment/configuration and managed paths. Reject foreign listeners, malformed route state, active routes, and detected coding-agent processes.
- Preserve T3 launcher ownership and existing drop-ins, then verify the effective executable after activation. HTTP alone is insufficient.
- Serialize cooperating installers and compare configuration/runtime against the saved baseline after candidate staging. Refuse intervening changes rather than overwrite them.
- For Portless, install the exact manifest version into a separate candidate directory using stable Node and disabled npm install scripts. Validate its entrypoint/version before selecting it.
- Preserve previous configuration bytes/mode and Portless selection. Activate deliberately, verify owned listeners and HTTP readiness, and restore on failure.
- Treat promotion failure as failure even when rollback succeeds. Report rollback failure explicitly for manual recovery.

The lock only coordinates these helpers. No userspace lock prevents unrelated software from starting new work during a maintenance window. SIGKILL, host power loss, and a broken service manager can prevent automatic recovery. Current Node formula patch changes are also outside this component transaction.

Legacy migration entrypoints refuse before any side effect. They must not stop old services and then discover that the hardened downstream installer rejects missing authorization. Their historical implementation remains in Git history for a separate reviewed cutover.

## Tests

```sh
python3 -B -m unittest discover -s dot_scripts/fleet_services -p 'test_installers.py' -v
python3 -B -m unittest discover -s tests -p 'test_fleet_audit.py' -v
```

Installer tests use temporary homes and fake command responses. They cover active-work refusal, zero-write defaults, listener ownership, deliberate activation, configuration/link/runtime restoration, explicit failed rollback, staging conflicts, effective override failure, preserved network drop-ins, and macOS LaunchAgent activation/refusal/recovery control flow.

See [fleet-maintenance-boundaries.md](fleet-maintenance-boundaries.md) for unchanged Caddy tooling and remaining live acceptance gates, and [compat-portless-isolated.md](compat-portless-isolated.md) for real routing tests and their failures.
