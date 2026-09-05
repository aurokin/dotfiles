# Fleet maintenance boundaries

This branch implements a bounded engineering pass, not a deployment authorization or an unattended updater. The September 1 deployment baseline remains historical.

## Evidence levels

- A unit test with fake service commands proves installer control flow only. It does not prove a real systemd or launchd cutover or rollback.
- A high-port isolated fixture proves the tested router/framework behavior with that runtime and temporary state. It does not replace production ingress, VPN, DNS, or browser secure-context acceptance.
- A missing-route HTTP response proves ingress only when the expected Portless response is identified. A generic 404 is insufficient.
- A T3 homepage returning 200 does not establish provider authentication, session execution, cancellation, or safe idle status.
- An unreachable host is unknown, not a failed deployment and not permission to wake, reboot, or change OS.

## Deployment gates still required

Before a future live apply, obtain authorization for the selected component and host, confirm exact host and OS identity, recheck active work, verify the current configuration and binary ownership, and preserve a usable rollback. Run one platform canary before any further promotion. Read back exact service state and exercise the application after activation. Report rollback as a failed promotion, even if restoration succeeds.

No quota-consuming Codex session, authentication change, T3 database migration, service restart, application quit, DNS write, package upgrade, or reboot is part of this pass.

## Unchanged scripts are not a transactional updater

Caddy package and service installers remain separate existing tools. They are not covered by the Portless/T3 hardening acceptance. Legacy migration entrypoints now refuse before any side effect because their old callers cannot satisfy the hardened installer's maintenance authorization:

- Caddy configuration helpers create temporary validation files in their default mode. They do not deploy without `--apply`, but that is not a zero-write audit mode.
- Caddy service helpers retain timestamped backups but do not automatically restore and verify them after every activation failure.
- The Linux package helper can invoke package lifecycle hooks. Its APT environment permits needrestart actions, and its Arch path selects the repository package before checking the expected version. Do not run it as a harmless candidate download or fleet update primitive.
- Reintroducing a legacy cutover requires a separately reviewed procedure that establishes idle and ownership before stopping any old service. Historical scripts remain available in Git history; removing the refusal is not a supported bypass.

Do not extend safety claims about the hardened helpers to these unchanged scripts. Before building fleet-wide apply, either harden the chosen additional component adapters or explicitly exclude them.

## Separate decisions

Keep desktop app lifecycle management separate from standalone CLI updates. Inventory bundled binaries independently. A process list cannot establish that an app is safe to quit.

Keep Mac login-session services distinct from unattended pre-login workers. Any T3 ownership migration must maintain one backend per T3 home and database.

Private HTTPS, Luma's roaming route, Webmux integration, actual project compatibility, and cold-boot behavior need their own evidence. Do not introduce public DNS, certificate credentials, or a second permanent fleet daemon to close unrelated checkboxes.
