# Read-only fleet audit

Run from the repository root with Python 3.9 or newer:

```sh
python3 -B dot_scripts/fleet_services/fleet_audit.py
python3 -B dot_scripts/fleet_services/fleet_audit.py --hosts koopa herb --workers 2 --timeout 45 --report /tmp/fleet-audit.json
python3 -B -m unittest discover -s tests -p test_fleet_audit.py -v
```

The default inventory covers koopa, metapod, luma, haste, mander, tortle, saur and herb. Remote targets are exactly `auro@HOST.home.arpa`. Local execution is allowed only for koopa when the current hostname and user match. `--ssh-only` disables that optimization.

SSH uses batch authentication, strict existing host-key verification, one connection attempt and bounded connection/liveness timeouts. The auditor never accepts a new host key. Unknown keys require separate human verification. Discovery runs `uname -s` before any Unix inventory payload. If Unix discovery fails without a transport failure, a bounded PowerShell identity query checks for Windows. Unix hostname and user must match before inventory begins; the inventory checks them again. Windows gets no Unix inventory, updates or service operations.

## Output and limits

Stdout is JSON with UTC start/finish timestamps and one result per requested host. `--report` also atomically writes a mode-0600 local report. Its parent directory must already exist. Keep reports outside the repository, such as `/tmp`, because host inventory is operational evidence, not source code. The CLI does not write remote files; Python runs with `-B` and receives its payload on stdin.

`--workers` bounds concurrent controller jobs to 1 through 8, default 4. Each Unix inventory subprocess has a hard `--timeout` deadline, default 45 seconds. Discovery has up to two additional 10-second stages. Each installed tool/service query has a 3-second deadline. HTTP socket operations use 3 seconds, response reads have an elapsed-time guard, and response bodies are capped at 1 MiB. Controller HTTP subprocesses have a hard 6-second deadline, including DNS. Each Unix inventory has at most two concurrent loopback HTTP requests. No probe retries or mutations run automatically.

Exit 0 means every requested Unix host inventory completed with matching identity. Exit 1 means at least one inventory could not complete; it does **not** mean every service failed. Service/HTTP failures do not change host inventory success. Exit 2 indicates invalid arguments. Read the JSON service and HTTP fields rather than treating the process exit code as a fleet-health verdict.

## Separate evidence dimensions

- Host `status` distinguishes `ok`, `timeout`, `offline`, `dns_error`, `auth_error`, `host_key_error`, `ssh_error`, `wrong_os`, identity errors and probe errors. Unavailable inventory is `null`, never an invented unhealthy service. Windows also has an independent `identity_status` because its machine name may differ from the Linux fleet hostname.
- `inventory.services` reads selected systemd properties or the `com.auro.portless` and `com.auro.caddy` launchd jobs. Linux process executable paths come from `/proc/PID/exe`, when readable. Permission-denied metadata is unknown, not missing. Macs report the T3 desktop ownership expectation without claiming to have proved exclusive database/process ownership. They do not expect a `com.t3code.server` job.
- `inventory.http` checks loopback Portless port 1355 and T3 port 3773 separately. `controller_http` independently probes `http://verify.HOST.home.arpa/` through the wildcard/Caddy ingress and `http://HOST.home.arpa:3773/` for external T3, even when SSH fails or the host boots Windows. HTTP observations do not authenticate machine identity.
- `missing_route_response` requires HTTP 404, the Portless missing-app text and `X-Portless: 1`. This proves a Portless proxy answered, not that an application route works. Other responses are `unexpected_response`. The controller's `verify` hostname must remain unregistered for this check to have its expected meaning. Redirects are not followed; environment HTTP proxies are disabled.
- T3 `http_ok` means HTTP 200 only. It does not establish server version, authentication, provider discovery, sessions, WebSocket compatibility or database safety. No provider calls are made.
- `tools_noninteractive_path` records selected executable paths, resolved symlinks, filesystem owners and bounded versions for Node, Caddy and Codex. Portless's managed package version comes from its package metadata. `stable_node` separately inventories the stable Node 24 path. `t3_runtime` includes the launcher path and allowlisted declared active version from upstream service state, not a claim about the responding process's version.
- `codex_standalone_candidates` is separate from PATH selection. A shell-selected npm or mise Codex may differ from `~/.local/bin/codex`. Installation hints describe path layout; they are not package-manager receipt checks. Noninteractive PATH is not an interactive alias/function inventory, and the auditor deliberately does not source interactive shell startup files.
- Mac app versions come from installed bundle plists, including `T3 Code (Alpha).app`. Bundle presence/version does not prove cask ownership or the version of a currently running desktop backend.

No response bodies, raw command lines, complete configs, environment values, credentials or raw subprocess errors enter the report. Metadata filenames and versions are retained. The audit does not establish idle-work readiness, detect all parallel T3 backends, authorize updates, restart services, change routes, or repair authentication.
