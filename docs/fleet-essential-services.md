# Fleet Essential Services

Document type: deployed ownership contract and remaining validation plan.
Last reviewed: 2026-09-01.

## Scope

The essential development/agent services are:

- Portless
- Caddy
- T3 Code
- Codex standalone CLI/app-server
- ChatGPT/Codex desktop app where supported
- one stable non-mise Node 24 LTS runtime for Node-backed services

Target development hosts:

```text
koopa
metapod
luma
haste (Linux side for this rollout)
mander
tortle
saur
herb
```

Bront and infra are not convenience development hosts. Haste Windows remains a separate desktop-app surface and is not part of the Linux service deployment.

## Core invariants

1. Interactive shells keep mise first on `PATH`.
2. Essential services never execute a version-specific mise install path.
3. Homebrew/Linuxbrew `node@24` provides the stable service Node path:
   - Apple Silicon macOS: `/opt/homebrew/opt/node@24/bin/node`
   - Linuxbrew: `/home/linuxbrew/.linuxbrew/opt/node@24/bin/node`
4. Portless's interactive CLI remains mise-managed and version-pinned.
5. The Portless proxy service is dotfiles-owned; do not use `portless service install` as the durable fleet owner.
6. Caddy owns network-facing port 80. Portless stays unprivileged and loopback-only on port 1355.
7. Service definitions set every Portless mode explicitly; they do not inherit shell state.
8. Tailscale remains DNS/transport only. No per-app Serve or Funnel registrations.
9. One T3 server process owns one `T3CODE_HOME` database.
10. Updates are audited and canary-promoted; none of these components auto-update fleet-wide.

## Portless service contract

The dotfiles-owned service runs the reviewed service copy of Portless with:

```text
PORTLESS_PORT=1355
PORTLESS_HTTPS=0
PORTLESS_LAN=0
PORTLESS_SYNC_HOSTS=0
PORTLESS_TLD=<host>.home.arpa,localhost
PORTLESS_STATE_DIR=~/.portless
```

The first TLD is the canonical URL returned to apps and agents. `localhost` remains a local compatibility route. Caddy forwards both host forms to the same loopback proxy.

The service copy is installed under a versioned user-owned root with an atomic `current` selection. Interactive `portless` remains mise-managed, but the update agent requires both copies to report the approved version before promotion.

Platform services:

- macOS: user LaunchAgent; starts at login.
- Linux: systemd user service with lingering enabled.

Legacy root Portless services on Koopa, Luma, Haste, and Herb were retired or disabled after transactional migration. All eight target hosts now use the dotfiles-owned user service. Retired service files remain available as rollback evidence; no legacy root Portless process is active.

## Caddy service contract

Caddy is the replaceable machine-level ingress:

```caddyfile
:80 {
    reverse_proxy 127.0.0.1:1355
}
```

Caddy preserves the request Host header and WebSocket upgrades. It has no dynamic per-app config; Portless owns route state.

Package sources:

- macOS: Homebrew Caddy is the accepted source; Caddy documents it as community-maintained for macOS. Dotfiles own the reviewed LaunchDaemon/config deployment.
- Ubuntu/Debian: use the exact reviewed official Caddy `.deb` and its native systemd service.
- CachyOS/Arch: use the native `caddy` package and systemd service.

Do not use Linuxbrew Caddy as the final Linux system-service package. The Linuxbrew binary installed for the Haste pilot may remain until native-package cutover is accepted.

## T3 ownership and updates

Linux/headless hosts use T3's upstream service launcher. Do not replace it: it installs immutable exact-version runtimes, snapshots SQLite state before trial migration, commits only after readiness, and rolls back failed candidates.

The update agent invokes the approved exact version through the stable service Node runtime:

```text
<service-node>/npx t3@<approved-version> service update
```

Required gates:

- no active agent/terminal work;
- enough disk for the temporary database snapshot;
- service endpoint returns HTTP 200 after reconnect;
- server reports the approved version;
- Codex provider discovery and one bounded session pass;
- rollback outcome is surfaced as failure, never success.

### Desktop-app exception

Do not run a background T3 service against the same `T3CODE_HOME` as an active T3 desktop backend. Upstream issue #6097 documents two backends opening the same SQLite database when port 3773 is already occupied. Until upstream enforces single ownership:

- Linux/headless hosts: service-owned server.
- Macs using the T3 desktop app: desktop-owned server; no parallel background service.
- A Mac can become service-owned only if its desktop backend is stopped/retired or a deliberately separate T3 home/environment is used.

Desktop-owned servers are updated through the desktop app/cask path, not `t3 service update`.

## Codex ownership and updates

The standalone CLI is managed by the official standalone installer and `codex update`, not mise. The update agent records and verifies:

```text
codex --version
codex login status
codex doctor
```

Then it verifies T3 provider discovery, one bounded session, and Remote reconnect where enabled. Desktop-bundled Codex runtimes are a separate surface and must not be inferred from the standalone version.

Desktop app management:

- macOS: inventory the actual app bundle version. Prefer Homebrew cask ownership where safely adoptable; `chatgpt` and `t3-code` are auto-updating casks, so the app bundle remains the version source of truth.
- Windows: inventory Microsoft Store/AppX/winget ownership when Haste is booted into Windows.
- Updates that require restart must wait for idle work, fully quit the app (not merely close its window), apply the approved update, relaunch, and verify the bundled app-server/Remote state.
- Personal app builds may retain their built-in updater; disabling it centrally can require managed workspace/MDM policy. The fleet agent must detect out-of-band app updates rather than assume exclusive update ownership.

## Update-agent design

The update system has two commands/phases:

```text
fleet-services audit
fleet-services apply --component <name> --hosts <ordered-list>
```

Audit is read-only and may run on a schedule. Apply is manual and transactional:

1. Load a versioned manifest and target-host inventory.
2. Verify host identity, OS, active work, package owner, current service, listeners, and free disk.
3. Install/download candidate without changing `current`.
4. Verify candidate version and checksum/provenance.
5. Promote one platform canary.
6. Verify service, URL, route, WebSocket, cleanup, provider, and app-specific gates.
7. Promote sequentially with a bounded delay.
8. Roll back the selected version/config when verification fails.
9. Atomically publish a per-host result and final fleet report.

Never update Node, Portless, Caddy, T3, and Codex across every host in one transaction. Preserve attribution and a known-good rollback.

## Deployed state and remaining gates

Deployed on 2026-09-01:

1. Stable non-mise `node@24` installed on all eight hosts; reviewed runtime resolved to Node `24.20.0`.
2. Portless `0.15.6` user services deployed on Koopa, Metapod, Luma, Haste Linux, Mander, Tortle, Saur, and Herb.
3. Caddy `2.11.4` system services deployed on all eight hosts.
4. Saur durable canary passed local/cross-host HTTP, WebSockets, abrupt child cleanup, and zero-restart checks.
5. Eight scoped Technitium wildcard CNAMEs deployed after a verified mini backup.
6. Linux T3 stable-Node overrides and disabled provider-update advisories are active on Haste, Saur, Mander, Tortle, and Herb. The same advisory policy is active on Metapod/Luma and persisted for Koopa's next controlled T3 restart.
7. Codex target is `0.151.0`. Tortle, Saur, Herb, Metapod, Haste, and Luma reached it; Herb and Metapod were migrated from npm ownership to standalone. Koopa remains `0.150.1` while long-lived Codex/app-server work is active. Mander's bootstrapped Remote Control updater advanced it to `0.152.0`; its separate updater loop was stopped without stopping the app-server.
8. Haste Linux passed a real reboot-persistence check for Portless, Caddy, wildcard ingress, T3, and Codex before its T3 Node/policy reconciliation.

Still required:

1. Reboot persistence and service readback for macOS launchd and Ubuntu systemd classes; CachyOS/systemd passed on Haste.
2. Astro, linked-worktree, Webmux, and real static-alias compatibility gates.
3. Koopa T3 restart when active work permits so its persisted no-advisory setting becomes live.
4. Reconcile Koopa and Mander to the next approved Codex canary when active work permits. Codex currently has no supported switch for the bootstrapped Remote Control updater; audit and stop `pid-update-loop` after Mander bootstrap/reboot until upstream adds one.
5. Implement the read-only fleet audit and transactional update-agent command surface described above.
