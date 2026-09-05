#!/usr/bin/env python3
"""Bounded, opt-in service installation; no fleet or migration orchestration.

Legacy migrate_legacy_portless_* callers pass only --apply and are deliberately
refused. They must not be used until their own authorization/preflight is updated.
--confirm-idle is an operator assertion covering sessions/terminals that process
inspection cannot prove idle, especially T3. It never overrides detected work.
No enable/disable, linger, system service, or ownership changes are performed.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import plistlib
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request


class Refusal(RuntimeError):
    pass


def run(*args, check=True):
    result = subprocess.run(args, text=True, capture_output=True, timeout=90)
    if check and result.returncode:
        raise Refusal(f"Command failed ({result.returncode}): {args[0]} {args[1:]}")
    return result


def owned(path, home, symlink=False):
    """Reject redirected managed paths, foreign owners and writable ancestors."""
    if not path.is_relative_to(home):
        raise Refusal(f"Managed path outside HOME: {path}")
    for item in (path, *path.parents):
        if item == home.parent:
            break
        if item.is_symlink() and not (item == path and symlink):
            raise Refusal(f"Unexpected symlink: {item}")
        if item.exists() or item.is_symlink():
            st = item.lstat()
            if st.st_uid != os.getuid() or (not item.is_symlink() and st.st_mode & 0o022):
                raise Refusal(f"Uncertain filesystem ownership: {item}")


def unit_state(name, user=True):
    args = ['systemctl'] + (['--user'] if user else [])
    result = run(*args, 'show', name, '--property=LoadState,ActiveState,FragmentPath,MainPID,DropInPaths,ExecStart')
    state = dict(line.split('=', 1) for line in result.stdout.splitlines() if '=' in line)
    if state.get('LoadState') not in ('loaded', 'not-found') or state.get('ActiveState') not in ('active', 'inactive', 'failed'):
        raise Refusal(f"Unknown or transitioning service state: {name}")
    if not state.get('MainPID', '').isdigit():
        raise Refusal(f"Unknown service PID: {name}")
    if state['ActiveState'] == 'active' and int(state['MainPID']) == 0:
        raise Refusal(f"Missing service PID: {name}")
    return state


def launch_state(domain, label):
    # Check the domain first: a broken/unavailable manager is not an absent job.
    run('launchctl', 'print', domain)
    result = run('launchctl', 'print', f'{domain}/{label}', check=False)
    if result.returncode:
        if 'Could not find service' not in result.stderr:
            raise Refusal('Cannot establish launchd ownership')
        return {'active': False, 'loaded': False, 'pid': 0}
    pid = re.search(r'^\s*pid = (\d+)\s*$', result.stdout, re.M)
    state = re.search(r'^\s*state = (.+)$', result.stdout, re.M)
    if not state or state[1] not in ('running', 'not running', 'waiting', 'exited'):
        raise Refusal('Unknown launchd state')
    if state[1] == 'running' and not pid:
        raise Refusal('Missing launchd PID')
    return {'active': state[1] == 'running', 'loaded': True, 'pid': int(pid[1]) if pid else 0,
            'description': result.stdout}


def listeners(port):
    result = run('lsof', '-nP', f'-iTCP:{port}', '-sTCP:LISTEN', '-t', check=False)
    if result.returncode == 1 and not result.stdout and not result.stderr:
        return set()
    if result.returncode or not result.stdout.strip():
        raise Refusal('Cannot establish listener ownership')
    try:
        return {int(v) for v in result.stdout.split()}
    except ValueError as exc:
        raise Refusal('Unrecognized listener inventory') from exc


def idle(kind, home):
    if kind == 'portless':
        routes = home / '.portless/routes.json'
        owned(routes, home)
        if routes.exists():
            data = json.loads(routes.read_text())
            if not isinstance(data, list) or data:
                raise Refusal('Portless routes are active or have unknown format')
    # This is only a veto, never evidence of idle. Explicit confirmation is required.
    processes = run('ps', '-axo', 'pid=,comm=').stdout
    for line in processes.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) != 2 or not fields[0].isdigit():
            raise Refusal('Cannot parse process inventory')
        executable = Path(fields[1]).name.lower()
        if executable in ('codex', 'claude', 'opencode', 'aider', 't3-code', 't3 code'):
            raise Refusal(f'Active agent/desktop process: {executable}')
    if not processes.strip():
        raise Refusal('Empty process inventory')


def atomic_write(path, data):
    fd, name = tempfile.mkstemp(prefix='.installer-', dir=path.parent)
    try:
        with os.fdopen(fd, 'wb') as out:
            out.write(data)
        os.replace(name, path)
    finally:
        if os.path.lexists(name):
            os.unlink(name)


def set_link(path, target):
    tmp = path.with_name('.installer-current')
    if os.path.lexists(tmp):
        raise Refusal(f'Stale current-link transaction: {tmp}')
    try:
        tmp.symlink_to(target)
        os.replace(tmp, path)
    finally:
        if tmp.is_symlink():
            tmp.unlink()


class Installer:
    def __init__(self, kind):
        self.kind = kind
        self.home = Path(os.environ['HOME']).absolute()
        self.os = platform.system()
        if self.os not in ('Linux', 'Darwin') or (kind == 't3' and self.os != 'Linux'):
            raise Refusal('Unsupported OS for this installer')
        self.node = Path('/opt/homebrew' if self.os == 'Darwin' else '/home/linuxbrew/.linuxbrew') / 'opt/node@24/bin/node'
        self.root = self.home / '.local/share/auro-services/portless'
        self.current = self.root / 'current'
        self.entry = self.current / 'node_modules/portless/dist/cli.js'
        self.launcher = self.home / '.t3/runtime/service-launcher.mjs'
        self.name = 'auro-portless.service' if kind == 'portless' else 't3code.service'
        self.unit = self.home / '.config/systemd/user' / self.name
        self.config = self.unit if kind == 'portless' else self.unit.with_name('t3code.service.d') / 'service-node.conf'
        self.domain = f'gui/{os.getuid()}'
        if self.os == 'Darwin':
            self.config = self.home / 'Library/LaunchAgents/com.auro.portless.plist'
        self.port = 1355 if kind == 'portless' else 3773
        self.version = None
        if kind == 'portless':
            text = Path(__file__).with_name('versions.env').read_text()
            match = re.search(r'^PORTLESS_VERSION=(\d+\.\d+\.\d+)$', text, re.M)
            if not match:
                raise Refusal('Invalid pinned Portless version')
            self.version = match[1]
        self.created_dirs = []

    def mkdir(self, path):
        missing = []
        while not path.exists():
            missing.append(path)
            path = path.parent
        for item in reversed(missing):
            item.mkdir(mode=0o700)
            self.created_dirs.append(item)

    def state(self):
        if self.os == 'Darwin':
            return launch_state(self.domain, 'com.auro.portless')
        raw = unit_state(self.name)
        if raw['LoadState'] == 'loaded':
            if raw.get('FragmentPath') != str(self.unit):
                raise Refusal('Service fragment is not the expected user unit')
            if self.kind == 'portless' and raw.get('DropInPaths', ''):
                raise Refusal('Portless drop-ins require manual review of route state/ownership')
            for value in raw.get('DropInPaths', '').split():
                dropin = Path(value)
                if dropin.parent != self.unit.with_name(self.name + '.d') or dropin.suffix != '.conf':
                    raise Refusal('Unreviewed service drop-in location')
                owned(dropin, self.home)
            expected = self.entry if self.kind == 'portless' else self.launcher
            argv = self.exec_argv(raw.get('ExecStart', ''))
            if len(argv) < 2 or argv[1] != str(expected) or Path(argv[0]).name not in ('node', 'bun'):
                raise Refusal('Service executable ownership is uncertain')
        return {'active': raw['ActiveState'] == 'active', 'loaded': raw['LoadState'] == 'loaded',
                'pid': int(raw['MainPID']), 'exec': raw.get('ExecStart', '')}

    @staticmethod
    def exec_argv(value):
        if 'argv[]=' in value:
            value = value.split('argv[]=', 1)[1].split(' ;', 1)[0]
        return value.split()

    def verify_effective(self):
        if self.os == 'Linux':
            argv = self.exec_argv(unit_state(self.name).get('ExecStart', ''))
            entry = self.entry if self.kind == 'portless' else self.launcher
            if argv[:2] != [str(self.node), str(entry)]:
                raise Refusal('Effective ExecStart does not use the candidate Node/entrypoint')

    def preflight(self):
        # Reject values that would require systemd escaping; plistlib handles XML.
        if not re.fullmatch(r'/[A-Za-z0-9_./-]+', str(self.home)):
            raise Refusal('HOME requires unsupported service-file escaping')
        for path in (self.config, self.unit, self.root, self.home / '.portless',
                     self.home / '.local/state/auro-services/portless'):
            owned(path, self.home)
        owned(self.current, self.home, symlink=True)
        if self.current.exists() and not self.current.is_symlink():
            raise Refusal('current is not a symlink')
        if self.current.is_symlink():
            target = self.current.resolve(strict=True)
            if not target.is_relative_to(self.root / 'versions'):
                raise Refusal('current points outside managed versions')
            owned(target, self.home)
        if self.kind == 't3':
            owned(self.launcher, self.home)
            if not self.launcher.is_file() or not self.unit.is_file():
                raise Refusal('Required T3 launcher/unit missing')
        if self.os == 'Linux' and self.kind == 'portless':
            legacy = unit_state('portless.service', user=False)
            if legacy['ActiveState'] != 'inactive' or legacy['MainPID'] != '0':
                raise Refusal('Legacy system Portless ownership is not inactive')
        elif self.os == 'Darwin':
            legacy = launch_state('system', 'sh.portless.proxy')
            if legacy['loaded']:
                raise Refusal('Legacy LaunchDaemon is still loaded')
        self.before = self.state()
        if self.os == 'Darwin' and self.before['loaded'] and not self.before['active']:
            raise Refusal('Inactive loaded LaunchAgent requires manual maintenance; cannot preserve its runtime state')
        if self.before['loaded'] and not self.config.is_file() and self.kind == 'portless':
            raise Refusal('Loaded service has no owned configuration')
        if self.os == 'Darwin' and self.before['loaded']:
            data = plistlib.loads(self.config.read_bytes())
            if data.get('Label') != 'com.auro.portless' or data.get('ProgramArguments', [])[:2] != [str(self.node), str(self.entry)]:
                raise Refusal('Unrecognized LaunchAgent configuration')
            if str(self.config) not in self.before['description']:
                raise Refusal('Loaded LaunchAgent path is not the managed plist')
        self.check_listener(self.before)
        idle(self.kind, self.home)
        if not self.node.is_file() or not os.access(self.node, os.X_OK):
            raise Refusal('Stable service Node 24 is missing')
        if run(str(self.node), '-p', 'process.versions.node.split(".")[0]').stdout.strip() != '24':
            raise Refusal('Expected service Node major 24')

    def owns_listeners(self, state, pids):
        if not state['active']:
            return False
        rows = run('ps', '-axo', 'pid=,ppid=,uid=').stdout.splitlines()
        try:
            tree = {int(pid): (int(ppid), int(uid)) for pid, ppid, uid in (row.split() for row in rows)}
        except ValueError as exc:
            raise Refusal('Cannot parse listener process ancestry') from exc
        for pid in pids:
            seen = set()
            while pid not in seen:
                seen.add(pid)
                if pid not in tree or tree[pid][1] != os.getuid():
                    return False
                if pid == state['pid']:
                    break
                pid = tree[pid][0]
            else:
                return False
        return bool(pids)

    def check_listener(self, state):
        pids = listeners(self.port)
        if pids and not self.owns_listeners(state, pids):
            raise Refusal('Listener is not exclusively owned by the managed service tree')

    def render(self):
        if self.kind == 't3':
            return f'[Service]\nExecStart=\nExecStart={self.node} {self.launcher}\n'.encode()
        host = platform.node().split('.')[0].lower()
        if not re.fullmatch('[a-z0-9][a-z0-9-]*', host):
            raise Refusal('Unsafe short hostname')
        logs = self.home / '.local/state/auro-services/portless/service.log'
        env = {'HOME': str(self.home), 'PORTLESS_STATE_DIR': str(self.home / '.portless'),
               'PORTLESS_PORT': '1355', 'PORTLESS_HTTPS': '0', 'PORTLESS_LAN': '0',
               'PORTLESS_SYNC_HOSTS': '0', 'PORTLESS_TLD': f'{host}.home.arpa,localhost'}
        args = [str(self.node), str(self.entry), 'proxy', 'start', '--foreground', '--port', '1355',
                '--no-tls', '--tld', f'{host}.home.arpa', '--tld', 'localhost']
        if self.os == 'Darwin':
            return plistlib.dumps({'Label': 'com.auro.portless', 'ProgramArguments': args,
                                   'EnvironmentVariables': env, 'RunAtLoad': True,
                                   'KeepAlive': {'SuccessfulExit': False}, 'ProcessType': 'Background',
                                   'StandardOutPath': str(logs), 'StandardErrorPath': str(logs)})
        return ('[Unit]\nDescription=Auro Portless development router\nAfter=network-online.target\n'
                '[Service]\nType=simple\nWorkingDirectory=%h\n' +
                ''.join(f'Environment={key}={value}\n' for key, value in env.items()) +
                f'ExecStart={" ".join(args)}\nRestart=on-failure\nRestartSec=3\n'
                f'KillSignal=SIGTERM\nTimeoutStopSec=10\nStandardOutput=append:{logs}\n'
                f'StandardError=append:{logs}\n[Install]\nWantedBy=default.target\n').encode()

    def stop(self):
        if self.os == 'Linux':
            run('systemctl', '--user', 'stop', self.name)
        elif launch_state(self.domain, 'com.auro.portless')['loaded']:
            run('launchctl', 'bootout', f'{self.domain}/com.auro.portless')
        if self.state()['active'] or listeners(self.port):
            raise Refusal('Managed runtime did not stop cleanly')

    def activate(self, restart):
        if self.os == 'Linux':
            run('systemctl', '--user', 'daemon-reload')
            run('systemctl', '--user', 'restart' if restart else 'start', self.name)
        else:
            self.stop()
            run('launchctl', 'bootstrap', self.domain, str(self.config))
            run('launchctl', 'kickstart', f'{self.domain}/com.auro.portless')

    def ready(self):
        # Ignore proxy environment. Redirects are not readiness, even to localhost.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs):
                return None
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        for _ in range(10):
            state = self.state()
            if self.owns_listeners(state, listeners(self.port)):
                headers = {'Host': 'installer-readiness-missing.invalid'} if self.kind == 'portless' else {}
                request = urllib.request.Request(f'http://127.0.0.1:{self.port}/', headers=headers)
                identity = None
                try:
                    with opener.open(request, timeout=2) as response:
                        status = response.status
                        identity = response.headers.get('X-Portless')
                except urllib.error.HTTPError as exc:
                    status = exc.code
                    identity = exc.headers.get('X-Portless')
                    exc.close()
                except (OSError, urllib.error.URLError):
                    status = 0
                # The deliberately absent hostname must reach Portless, not an app.
                if (self.kind == 'portless' and status == 404 and identity == '1') or (self.kind == 't3' and status == 200):
                    return
            time.sleep(0.5)
        raise Refusal('Managed service failed HTTP readiness')

    def config_snapshot(self):
        paths = {self.unit, self.config}
        paths.update(self.unit.with_name(self.name + '.d').glob('*.conf'))
        if self.kind == 't3':
            paths.add(self.launcher)
        else:
            paths.add(self.entry)
        snapshot = {}
        for path in paths:
            snapshot[str(path)] = (path.read_bytes(), path.stat().st_mode) if path.exists() else None
        snapshot['current'] = os.readlink(self.current) if self.current.is_symlink() else None
        return snapshot

    def apply(self):
        # Read-only guards before even creating the lock. Repeat under the lock.
        self.preflight()
        stage = None
        installed = None
        old_config, old_link, old_mode = None, None, 0o600
        changed = False
        runtime_attempted = False
        lock = self.home / f'.{self.kind}-installer.lock'
        owned(lock, self.home)
        lock.mkdir(mode=0o700)
        try:
            self.preflight()
            config_data = self.render()
            old_config = self.config.read_bytes() if self.config.exists() else None
            old_mode = self.config.stat().st_mode & 0o777 if self.config.exists() else 0o600
            old_link = os.readlink(self.current) if self.current.is_symlink() else None
            baseline = self.before.copy()
            baseline_files = self.config_snapshot()
            if self.kind == 'portless':
                versions = self.root / 'versions'
                assert self.version is not None
                candidate = versions / self.version
                owned(candidate, self.home)
                entry_rel = Path('node_modules/portless/dist/cli.js')
                self.mkdir(versions)
                if not candidate.exists():
                    stage = Path(tempfile.mkdtemp(prefix='.installer-stage-', dir=self.root))
                    npm_cli = self.node.with_name('npm').resolve(strict=True)
                    run(str(self.node), str(npm_cli), 'install', '--prefix', str(stage), '--omit=dev',
                        '--no-audit', '--no-fund', '--ignore-scripts', f'portless@{self.version}')
                    if not (stage / entry_rel).is_file() or run(str(self.node), str(stage / entry_rel), '--version').stdout.strip() != self.version:
                        raise Refusal('Candidate version/entrypoint validation failed')
                    stage.rename(candidate)
                    stage = None
                    installed = candidate
                if not (candidate / entry_rel).is_file() or run(str(self.node), str(candidate / entry_rel), '--version').stdout.strip() != self.version:
                    raise Refusal('Installed candidate version/entrypoint validation failed')
            # Downloads may take time. Re-check work, ownership and runtime before cutover.
            self.preflight()
            if self.before != baseline or self.config_snapshot() != baseline_files:
                raise Refusal("Service/configuration changed during staging; refusing cutover")
            self.before = baseline
            self.mkdir(self.config.parent)
            changed = True
            if self.kind == 'portless':
                self.mkdir(self.home / '.portless')
                self.mkdir(self.home / '.local/state/auro-services/portless')
                set_link(self.current, f'versions/{self.version}')
            atomic_write(self.config, config_data)
            if self.os == 'Linux':
                run('systemd-analyze', '--user', 'verify', str(self.unit))
            else:
                run('plutil', '-lint', str(self.config))
            runtime_attempted = True
            self.activate(restart=self.before['active'])
            self.verify_effective()
            self.ready()
        except BaseException:
            failures = []
            def restore(label, action):
                try:
                    action()
                except BaseException as exc:
                    failures.append(f'{label}: {exc}')
            if runtime_attempted:
                restore('stop failed candidate', self.stop)
            stopped = not failures
            if changed:
                if old_config is None:
                    restore('remove candidate configuration', lambda: self.config.unlink(missing_ok=True))
                else:
                    restore('restore configuration', lambda: atomic_write(self.config, old_config))
                    restore('restore configuration mode', lambda: self.config.chmod(old_mode))
                if self.kind == 'portless':
                    if old_link is None:
                        restore('remove current link', lambda: self.current.unlink(missing_ok=True))
                    else:
                        restore('restore current link', lambda: set_link(self.current, old_link))
                if runtime_attempted and stopped:
                    if self.os == 'Linux':
                        restore('reload old configuration', lambda: run('systemctl', '--user', 'daemon-reload'))
                    if self.before['active']:
                        restore('restart old runtime', lambda: self.activate(restart=False))
                        restore('old runtime readiness', self.ready)
                    elif self.os == 'Darwin' and self.before['loaded']:
                        # Refused in preflight below: loading RunAtLoad jobs cannot preserve inactivity.
                        failures.append('Cannot restore inactive loaded launchd job')
                    else:
                        def verify_stopped():
                            if self.state()['active'] or listeners(self.port):
                                raise Refusal('Candidate remains active')
                        restore('verify stopped runtime', verify_stopped)
            if installed and not failures and self.current.resolve() != installed:
                restore('remove failed version', lambda: shutil.rmtree(installed))
            if failures:
                raise Refusal('ROLLBACK FAILED; manual recovery required: ' + '; '.join(failures))
            raise
        finally:
            if stage:
                shutil.rmtree(stage)
            lock.rmdir()
            for directory in reversed(self.created_dirs):
                try:
                    directory.rmdir()
                except OSError:
                    pass


def main(kind, argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--apply', action='store_true', help='write and activate after all guards pass')
    parser.add_argument('--allow-restart', action='store_true', help='authorize activation and rollback restarts')
    parser.add_argument('--confirm-idle', action='store_true', help='assert no active sessions/terminals or competing desktop backend')
    args = parser.parse_args(argv)
    if not args.apply:
        print(f'Read-only plan: install {kind}; no files, downloads or service changes. '
              'Apply requires --apply --allow-restart --confirm-idle. Existing enablement is preserved.')
        return 0
    if not args.allow_restart or not args.confirm_idle:
        parser.error('--apply requires --allow-restart and --confirm-idle; legacy migration callers are deliberately refused')
    def interrupted(signum, frame):
        raise Refusal(f'Interrupted by signal {signum}')
    signal.signal(signal.SIGTERM, interrupted)
    try:
        installer = Installer(kind)
        installer.apply()
    except (Refusal, OSError, ValueError, subprocess.SubprocessError) as exc:
        print(f'Installer refused/failed: {exc}', file=sys.stderr)
        return 1
    print(f'{kind}: configuration and runtime activated; HTTP readiness verified. Enablement unchanged.')
    return 0


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in ('portless', 't3'):
        raise SystemExit('Expected installer kind: portless or t3')
    raise SystemExit(main(sys.argv[1], sys.argv[2:]))
