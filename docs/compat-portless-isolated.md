# Isolated Portless compatibility

## Result

The reviewed local run started at `2026-09-05T02:52:49Z` with installed Portless `0.15.6` and Node `v24.20.0`. It recorded 17 passes, one failure, and two deferred groups. The runner exits 1 because the abrupt-cleanup failure is real, not an expected-pass assertion.

Evidence lives outside this repository:

- `/Users/auro/workspace/fleet-maintenance-evidence/compat-macos-reviewed.json`, rerun after portability and bounded WebSocket EOF handling, including cleanup verification.
- `/Users/auro/workspace/fleet-maintenance-evidence/compat-portless-isolated-results.json`, earlier local observations.
- `/Users/auro/workspace/fleet-maintenance-evidence/compat-portless-first-run.json`, initial observations. Its normal/SIGTERM failures were test timing defects corrected by waiting for the proxy's debounced route reload. Its Astro HMR deferral was resolved by a disposable pinned WebSocket client dependency.

## Reproduce

From this worktree:

```sh
python3 dot_scripts/compat-portless-isolated.py --astro \
  --report /Users/auro/workspace/fleet-maintenance-evidence/compat-portless-isolated-results.json
```

The runner supports macOS and Linux. It selects stable Node 24 at `/opt/homebrew/opt/node@24/bin/node` on macOS or `/home/linuxbrew/.linuxbrew/opt/node@24/bin/node` on Linux, and discovers `lsof` with `shutil.which`. It requires the already installed Portless version and system Git. It refuses other Portless versions pending source review. The source contract check is not a security audit or protection against a modified installation.

The Saur Linux canary also recorded 17 passes, one real SIGKILL failure, and two deferred groups. See [Linux canary evidence and portability notes](fleet-portless-compatibility.md). The revised script was subsequently rerun on both platforms with the same result counts.

`--astro` installs direct dependencies `astro@5.13.5` and `ws@8.18.3` in a temporary directory with install scripts disabled. Transitive dependencies are resolved by npm and are not lockfile-pinned across runs. No packages are installed globally. Without the flag, framework tests are deferred.

## Passed

- Proxy listens on IPv4 and IPv6 loopback. Fixture backend listens on IPv4 loopback.
- Real HTTP preserves Host, supplies the assigned PORT, and supplies the custom-suffix PORTLESS_URL.
- Real WebSocket upgrade validates the accept key and echoes a masked text frame through the proxy.
- Normal child exit and wrapper SIGTERM remove the backend and route. HTTP eventually returns 404.
- Static aliases register as PID 0, serve real HTTP, and can be removed without stopping their independently launched backend.
- A subsequent isolated alias mutation removes stale route ownership from disk and the proxy cache.
- A disposable orphan-branch linked Git worktree receives `compat-linked.compat-astro.compat.invalid`. No commits are created.
- Astro serves HTML through that route. A `vite-hmr` WebSocket receives `connected`, then `full-reload` after a page edit. Subsequent HTTP contains the edit.
- Astro SIGTERM removes its route.
- Final verification found no recorded owned PIDs alive, no listeners on any allocated port, and an empty temporary route registry. The temporary tree was removed. `/etc/hosts` matched its exact pre-run bytes.

## Failed

`sigkill_automatic_cleanup`: one second after SIGKILL of the Portless wrapper, the backend remained alive, the route remained on disk, and HTTP still returned 200. This failure reproduced across runs. It is evidence of failed immediate automatic cleanup, not a claim that the route survives indefinitely.

The test stopped only its recorded backend PID. A later alias mutation caused the stale route to disappear. It deliberately did not run `portless prune`, whose cleanup may target listeners by port.

## Deferred and limits

- Browser rendering and browser-driven HMR were not tested. Protocol messages and refreshed HTML were tested.
- Astro uses explicit loopback host and high-port flags. Automatic framework flag injection was not exercised.
- Next, Webmux, multi-app workspaces, and existing application repositories were not tested or modified.
- LAN/VPN reachability, TLS, proxy restart recovery, and reboot/service persistence remain deferred. Linux loopback coverage is now verified separately on Saur. No offline host was required.
- Tests use loopback HTTP and a custom `.compat.invalid` suffix with Host headers, not DNS resolution.
- Every proxy and app uses separate temporary state and high ports. TLS, LAN mode, hosts sync, and wildcard routing are explicitly disabled. No service manager, DNS, trust-store, ingress port, or live application operation occurs.

The original pre-review run owned PIDs were `92686, 92691, 92692, 92696, 92697, 92708, 92709, 92717, 92727, 92736`. Allocated ports were `53754, 53758, 53775, 53787, 53796, 53824`. These are evidence identifiers only, never cleanup instructions for later sessions.
