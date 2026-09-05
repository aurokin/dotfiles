# Fleet Portless compatibility

## Saur Linux canary

Point-in-time evidence, not a live fleet health assertion. The final run started at `2026-09-05T02:54:03Z` on verified Linux host `saur`, user `auro`, through `auro@saur.home.arpa` with strict SSH host-key checking. Installed Portless was `0.15.6`; stable Linuxbrew Node was `v24.20.0`.

The fixture exited **1** with **17 passes, one failure, and two deferred groups**. The failure remains a failure. The installed CLI SHA-256 matched the earlier macOS run, `f9c03862c2b36fb93b3aca2460bce46cf70a2a7e2de8cca1406d4e1376826866`.

| Check | Actual result |
| --- | --- |
| Proxy binding | Pass, `127.0.0.1` and `::1` on a high port |
| Backend binding | Pass, IPv4 loopback |
| HTTP Host, assigned PORT, PORTLESS_URL | Pass |
| WebSocket upgrade and masked echo | Pass |
| Normal exit cleanup | Pass, backend gone and route returns 404 |
| Wrapper SIGTERM cleanup | Pass, backend gone and route returns 404 |
| Wrapper SIGKILL automatic cleanup | **Fail**, backend alive, raw route retained, HTTP 200 after one second |
| Static alias HTTP | Pass, PID 0 alias |
| Stale route cleanup on mutation | Pass after stopping only the recorded orphan backend |
| Alias removal preserves independent backend | Pass |
| Astro linked orphan-branch worktree HTTP | Pass, `compat-linked.compat-astro.compat.invalid` |
| Astro HMR WebSocket | Pass, `connected` then `full-reload` following the page edit |
| Astro updated HTTP | Pass, edited HTML served |
| Astro SIGTERM route cleanup | Pass |
| Final owned PIDs and listeners | Pass |
| Final temporary routes empty | Pass |
| `/etc/hosts` byte comparison | Pass, unchanged |
| Temporary fixture deletion | Pass |

A separate SSH readback found all ten recorded PIDs absent and all six allocated ports without listeners. Both the fixture tree and unique transfer directory were removed. These are historical ownership identifiers, not instructions to kill those PIDs in another session.

## Isolation and portability changes

- Detect macOS or Linux and select the stable OS-specific Homebrew Node 24 path. Never fall back to an ambient version-manager Node.
- Discover `lsof` with `shutil.which`. Exit 0 with output is observed evidence; warnings accompanying observed output are retained in the report. Only exit 1 with empty stdout and stderr means no listener. Other outcomes raise or record uncertainty.
- A PID already confirmed absent by `kill(pid, 0)` cannot own sockets. Avoid querying Linux `lsof -p` for that absent PID, which produced unrelated snap mount warnings on this host. Final port-wide checks still run independently.
- Continue each owned cleanup attempt after an individual failure. Record errors and preserve the temporary tree when cleanup is uncertain.
- Discover the installed package under the current user's HOME, then run Node, npm, Portless, Git, and fixture children with a temporary HOME, XDG directories, npm config paths, state, and TMPDIR. Only locale/timezone variables survive from the inherited environment. No inherited credentials or Node options reach children.
- Inspect the installed source before any Portless command. The remote preflight captured state-directory, discovery, hosts-sync, TLS, LAN, and bind-target controls, including the imported hosts-sync helper.
- Transfer only the fixture script. Disposable dependencies are `astro@5.13.5` and `ws@8.18.3`, with npm install scripts disabled. Transitive versions are not locked across runs.
- Do not run `prune`, service commands, production restart/upgrade operations, DNS writes, trust changes, or credential operations. All test listeners use high loopback ports and explicit isolated state.

## Evidence

All paths below are under `/Users/auro/workspace/fleet-maintenance-evidence/`:

- `compat-portless-saur-results.json`: final granular results, source hash, logs, warnings, owned PIDs and ports.
- `compat-saur-preflight.json`: verified identity and inspected installed-source excerpts.
- `compat-saur-transport.json`: unique remote directory and transferred fixture SHA-256.
- `compat-saur-execution.json`: actual SSH fixture exit status, stdout, and stderr.
- `compat-saur-cleanup.json`: independent process/listener readback and confirmed remote directory removal.
- `compat-saur-driver.txt`: final driver output.
- `run-saur-compat.py`: local transport driver, not transferred to Saur. Its successful exit means transport/report collection succeeded, not that the canary passed. Inspect the saved fixture exit and results.
- `test-compat-portability.py` and `compat-portability-tests.txt`: three passing unit tests with subcases for OS paths, tool discovery, observed/empty/error/warning lsof results, and timeout propagation. These mock tool outcomes only to test the helper contract; they are not canary evidence.
- `compat-portless-saur-results-first-run.json` and `compat-portless-saur-results-second-run.json`: preserved incomplete attempts blocked by overly broad treatment of Linux snap mount warnings. Matching preflight, transport, execution, and cleanup files carry the same suffixes.
- `compat-portless-saur-results-third-run.json`: the first complete Linux run, also 17 passes, one SIGKILL failure, and two deferred groups. The final run revalidated the script after guarding log reads and closes during cleanup.
- `compat-portless-isolated-results.json`: unchanged earlier macOS result. See [the original report](compat-portless-isolated.md).

The first remote source preflight stopped before transfer because the hosts-sync definition lived in an imported chunk rather than `cli.js`. The subsequent preflight inspected all installed distribution JavaScript for that helper. No compatibility commands ran during the failed preflight.

## Remaining limits

LAN/VPN reachability, TLS, production applications, restart/reboot persistence, browser rendering, automatic framework flag injection, Next, Webmux, and multi-app repositories remain untested. The two deferred report groups cover these broader compatibility boundaries. Astro HTML and HMR protocol checks are not browser rendering or approval to migrate real applications.

The revised script was rerun on macOS and Linux after fixing bounded WebSocket EOF handling. `compat-macos-reviewed.json` records the macOS rerun. Both platforms again recorded 17 passes, one genuine abrupt-cleanup failure, and two deferred groups. Portability and receive-loop regression tests are now in repository `tests/test_compat_portability.py` and `tests/test_compat_receive.py`.
