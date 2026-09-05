"""Isolated installer tests: no real service commands, installs or live apply."""
import importlib.util
import hashlib
import shutil
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('installer_transaction', HERE / 'installer_transaction.py')
assert spec is not None and spec.loader is not None
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class FakeHost:
    def __init__(self, installer, active=True):
        self.i = installer
        self.active = active
        self.loaded = True
        self.calls = []
        self.fail_start = 0
        self.fail_verify = False
        self.bad_fragment = False
        self.legacy_unknown = False
        self.foreign_listener = False
        self.processes = '1 init\n'
        self.ancestry = f'1 0 0\n123 1 {os.getuid()}\n456 123 {os.getuid()}\n'
        self.listener = '123'
        self.dropins = ''
        self.on_install = lambda: None

    def run(self, *args, check=True):
        self.calls.append(args)
        stdout = ''
        rc = 0
        if args[:2] == (str(self.i.node), str(self.i.node.with_name('npm'))):
            stage = Path(args[args.index('--prefix') + 1])
            entry = stage / 'node_modules/portless/dist/cli.js'
            entry.parent.mkdir(parents=True)
            entry.write_text('candidate')
            if self.on_install:
                self.on_install()
        elif args[0] == str(self.i.node):
            stdout = '24\n' if '-p' in args else self.i.version or '24'
        elif args[0] == 'ps':
            stdout = self.ancestry if args[-1] == 'pid=,ppid=,uid=' else self.processes
        elif args[0] == 'lsof':
            stdout = '999\n' if self.foreign_listener else (self.listener + '\n' if self.active else '')
            rc = 0 if stdout else 1
        elif args[0] == 'systemd-analyze':
            rc = 1 if self.fail_verify else 0
        elif args[0] == 'systemctl':
            if 'show' in args:
                legacy = '--user' not in args
                if legacy and self.legacy_unknown:
                    rc = 1
                else:
                    active = False if legacy else self.active
                    loaded = False if legacy else self.loaded
                    fragment = '/foreign.service' if self.bad_fragment else str(self.i.unit)
                    entry = self.i.entry if self.i.kind == 'portless' else self.i.launcher
                    stdout = (f'LoadState={"loaded" if loaded else "not-found"}\n'
                              f'ActiveState={"active" if active else "inactive"}\n'
                              f'MainPID={123 if active else 0}\nFragmentPath={fragment}\n'
                              f'DropInPaths={self.dropins}\nExecStart={self.i.node} {entry}\n')
            elif 'stop' in args:
                self.active = False
            elif 'restart' in args or 'start' in args:
                if self.fail_start:
                    self.fail_start -= 1
                    rc = 1
                else:
                    self.active = True
                    self.loaded = True
        else:
            raise AssertionError(f'Unmocked command: {args}')
        if check and rc:
            raise m.Refusal(f'Mocked command failed: {args}')
        return subprocess.CompletedProcess(args, rc, stdout, '')


class Installers(unittest.TestCase):
    maxDiff = 1500

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='installers-')
        # macOS /var is a symlink: resolve the test HOME, just as a real home is.
        self.home = Path(self.temp.name).resolve() / 'home'
        self.home.mkdir(mode=0o700)
        self.env = patch.dict(os.environ, HOME=str(self.home))
        self.env.start()
        self.os_patch = patch.object(m.platform, 'system', return_value='Linux')
        self.os_patch.start()
        self.host_patch = patch.object(m.platform, 'node', return_value='fixture')
        self.host_patch.start()
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.env.stop)
        self.addCleanup(self.os_patch.stop)
        self.addCleanup(self.host_patch.stop)

    def fixture(self, kind='portless', active=True):
        i = m.Installer(kind)
        i.node = self.home / 'node/bin/node'
        i.node.parent.mkdir(parents=True)
        i.node.write_text('not executed')
        i.node.chmod(0o700)
        i.node.with_name('npm').write_text('mock npm-cli')
        i.unit.parent.mkdir(parents=True)
        i.unit.write_text('old unit\n')
        if kind == 'portless':
            previous = i.root / 'versions/old/node_modules/portless/dist/cli.js'
            previous.parent.mkdir(parents=True)
            previous.write_text('old runtime')
            i.current.symlink_to('versions/old')
        else:
            i.launcher.parent.mkdir(parents=True)
            i.launcher.write_text('old launcher')
            i.config.parent.mkdir()
            i.config.write_text('old override\n')
        i.config.chmod(0o640)
        host = FakeHost(i, active)
        return i, host

    def invoke(self, i, host, readiness=None):
        with patch.object(m, 'run', side_effect=host.run), patch.object(i, 'ready', side_effect=readiness):
            i.apply()

    def snapshot(self):
        return {str(p.relative_to(self.home)): ('link', os.readlink(p)) if p.is_symlink()
                else ('dir',) if p.is_dir() else ('file', hashlib.sha256(p.read_bytes()).hexdigest(), p.stat().st_mode & 0o777)
                for p in self.home.rglob('*')}

    def test_default_and_extra_arguments_never_write_or_probe(self):
        for kind, script in [('portless', 'install_portless_service.sh'), ('t3', 'install_t3_node_override.sh')]:
            for args, status in [([], 0), (['--apply'], 2), (['--apply', '--extra'], 2),
                                 (['--apply', '--allow-restart'], 2), (['oops'], 2)]:
                with self.subTest(kind=kind, args=args):
                    before = self.snapshot()
                    result = subprocess.run(['bash', str(HERE / script), *args], env=os.environ,
                                            text=True, capture_output=True, timeout=10)
                    self.assertEqual(result.returncode, status, result.stderr)
                    self.assertEqual(self.snapshot(), before)
        with patch.object(m, 'Installer', side_effect=AssertionError('default must not probe')):
            self.assertEqual(m.main('portless', []), 0)

    def test_active_service_deliberately_restarted_not_enabled(self):
        i, host = self.fixture()
        self.invoke(i, host)
        self.assertIn(('systemctl', '--user', 'restart', i.name), host.calls)
        self.assertTrue(host.active)
        self.assertEqual(os.readlink(i.current), 'versions/' + i.version)
        self.assertFalse(any('enable' in c or 'disable' in c or 'loginctl' in c for c in host.calls))
        self.assertIn('--ignore-scripts', next(c for c in host.calls if len(c) > 1 and c[1].endswith('/npm')))

    def test_inactive_service_starts_only_with_apply_and_preserves_enablement(self):
        i, host = self.fixture(active=False)
        self.invoke(i, host)
        self.assertIn(('systemctl', '--user', 'start', i.name), host.calls)
        self.assertNotIn(('systemctl', '--user', 'restart', i.name), host.calls)
        self.assertFalse(any('enable' in c or 'disable' in c for c in host.calls))

    def test_failed_activation_restores_config_link_runtime_and_mode(self):
        i, host = self.fixture()
        before = self.snapshot()
        host.fail_start = 1
        with self.assertRaises(m.Refusal):
            self.invoke(i, host)
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(host.active)
        self.assertIn(('systemctl', '--user', 'start', i.name), host.calls)

    def test_failed_readiness_restores_previous_and_verifies_rollback(self):
        i, host = self.fixture()
        before = self.snapshot()
        with self.assertRaisesRegex(m.Refusal, 'not ready'):
            self.invoke(i, host, [m.Refusal('not ready'), None])
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(host.active)

    def test_failed_inactive_activation_restores_inactive(self):
        i, host = self.fixture(active=False)
        before = self.snapshot()
        with self.assertRaises(m.Refusal):
            self.invoke(i, host, [m.Refusal('not ready')])
        self.assertFalse(host.active)
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(any('enable' in c or 'disable' in c for c in host.calls))

    def test_failed_config_validation_does_not_stop_existing_runtime(self):
        i, host = self.fixture()
        before = self.snapshot()
        host.fail_verify = True
        with self.assertRaises(m.Refusal):
            self.invoke(i, host)
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(host.active)
        self.assertNotIn(('systemctl', '--user', 'stop', i.name), host.calls)

    def test_failed_rollback_is_explicit_and_retains_candidate(self):
        i, host = self.fixture()
        with self.assertRaisesRegex(m.Refusal, 'ROLLBACK FAILED'):
            self.invoke(i, host, [m.Refusal('new failed'), m.Refusal('old failed')])
        self.assertEqual(os.readlink(i.current), 'versions/old')
        self.assertEqual(i.config.read_text(), 'old unit\n')
        self.assertTrue((i.root / 'versions' / i.version).exists())

    def test_active_malformed_and_unknown_routes_refused_before_download(self):
        for routes in ('[{"hostname":"busy"}]', '{"routes":[]}', 'not json', 'null'):
            with self.subTest(routes=routes):
                i, host = self.fixture()
                route = self.home / '.portless/routes.json'
                route.parent.mkdir()
                route.write_text(routes)
                before = self.snapshot()
                with self.assertRaises((m.Refusal, ValueError)):
                    self.invoke(i, host)
                self.assertEqual(self.snapshot(), before)
                self.assertFalse(any(len(c) > 1 and c[1].endswith('/npm') for c in host.calls))
                for p in self.home.iterdir():
                    shutil.rmtree(p) if p.is_dir() else p.unlink()

    def test_unknown_legacy_foreign_fragment_and_listener_refused(self):
        for field in ('legacy_unknown', 'bad_fragment', 'foreign_listener'):
            with self.subTest(field=field):
                i, host = self.fixture()
                setattr(host, field, True)
                before = self.snapshot()
                with self.assertRaises(m.Refusal):
                    self.invoke(i, host)
                self.assertEqual(self.snapshot(), before)
                shutil.rmtree(self.home)
                self.home.mkdir(mode=0o700)

    def test_active_agents_veto_explicit_idle_assertion(self):
        i, host = self.fixture('t3')
        host.processes = '1 init\n200 /usr/bin/codex\n'
        before = self.snapshot()
        with self.assertRaisesRegex(m.Refusal, 'Active agent'):
            self.invoke(i, host)
        self.assertEqual(self.snapshot(), before)

    def test_t3_override_rolls_back_without_modifying_launcher(self):
        i, host = self.fixture('t3')
        before = self.snapshot()
        with self.assertRaises(m.Refusal):
            self.invoke(i, host, [m.Refusal('failed HTTP'), None])
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(host.active)

    def test_symlinked_config_refused(self):
        i, host = self.fixture()
        i.config.unlink()
        target = self.home / 'outside'
        target.write_text('untouched')
        i.config.symlink_to(target)
        before = self.snapshot()
        with self.assertRaisesRegex(m.Refusal, 'symlink'):
            self.invoke(i, host)
        self.assertEqual(self.snapshot(), before)

    def test_concurrent_lock_is_not_removed(self):
        i, host = self.fixture()
        lock = self.home / '.portless-installer.lock'
        lock.mkdir()
        before = self.snapshot()
        with self.assertRaises(FileExistsError):
            self.invoke(i, host)
        self.assertEqual(self.snapshot(), before)

    def test_http_readiness_requires_service_listener_and_http_status(self):
        i, host = self.fixture('t3')
        with patch.object(m, 'run', side_effect=host.run), patch.object(m.time, 'sleep'), \
             patch.object(m.urllib.request, 'build_opener') as build:
            build.return_value.open.return_value.__enter__.return_value.status = 200
            i.ready()
            build.return_value.open.return_value.__enter__.return_value.status = 503
            with self.assertRaisesRegex(m.Refusal, 'HTTP readiness'):
                i.ready()
            host.foreign_listener = True
            build.return_value.open.reset_mock()
            with self.assertRaises(m.Refusal):
                i.ready()
            build.return_value.open.assert_not_called()


    def mac_fixture(self):
        i, host = self.fixture()
        i.os = 'Darwin'
        i.config = self.home / 'Library/LaunchAgents/com.auro.portless.plist'
        i.config.parent.mkdir(parents=True)
        i.config.write_bytes(i.render())
        i.config.chmod(0o640)
        original_run = host.run

        def launch_state(domain, label):
            if domain == 'system':
                return {'active': False, 'loaded': False, 'pid': 0}
            return {'active': host.active, 'loaded': host.loaded,
                    'pid': 123 if host.active else 0, 'description': str(i.config)}

        def run(*args, check=True):
            if args[0] not in ('launchctl', 'plutil'):
                return original_run(*args, check=check)
            host.calls.append(args)
            if args[0] == 'launchctl':
                if args[1] == 'bootout':
                    host.active = host.loaded = False
                elif args[1] == 'bootstrap':
                    if host.fail_start:
                        host.fail_start -= 1
                        raise m.Refusal('mock bootstrap failed')
                    host.active = host.loaded = True
            return subprocess.CompletedProcess(args, 0, '', '')

        return i, host, launch_state, run

    def test_macos_activation_uses_owned_launchagent(self):
        i, host, state, run = self.mac_fixture()
        with patch.object(m, 'launch_state', side_effect=state), patch.object(m, 'run', side_effect=run), patch.object(i, 'ready'):
            i.apply()
        self.assertTrue(host.active)
        self.assertIn(('launchctl', 'bootout', i.domain + '/com.auro.portless'), host.calls)
        self.assertIn(('launchctl', 'bootstrap', i.domain, str(i.config)), host.calls)
        self.assertEqual(os.readlink(i.current), 'versions/' + i.version)

    def test_macos_bootstrap_failure_restores_configuration_and_runtime(self):
        i, host, state, run = self.mac_fixture()
        before = self.snapshot()
        host.fail_start = 1
        with patch.object(m, 'launch_state', side_effect=state), patch.object(m, 'run', side_effect=run), patch.object(i, 'ready'):
            with self.assertRaisesRegex(m.Refusal, 'bootstrap failed'):
                i.apply()
        self.assertTrue(host.active)
        self.assertEqual(self.snapshot(), before)

    def test_macos_loaded_inactive_job_is_refused_without_mutation(self):
        i, host, state, run = self.mac_fixture()
        host.active = False
        before = self.snapshot()
        with patch.object(m, 'launch_state', side_effect=state), patch.object(m, 'run', side_effect=run):
            with self.assertRaisesRegex(m.Refusal, 'Inactive loaded LaunchAgent'):
                i.apply()
        self.assertEqual(self.snapshot(), before)
        self.assertFalse(any(c[0] == 'launchctl' for c in host.calls))

    def test_staging_conflict_preserves_external_configuration(self):
        i, host = self.fixture()
        host.on_install = lambda: i.config.write_text('external change\n')
        with self.assertRaisesRegex(m.Refusal, 'changed during staging'):
            self.invoke(i, host)
        self.assertEqual(i.config.read_text(), 'external change\n')
        self.assertEqual(os.readlink(i.current), 'versions/old')
        self.assertFalse(any('restart' in c or 'stop' in c for c in host.calls))

    def test_effective_override_failure_triggers_rollback(self):
        i, host = self.fixture('t3')
        before = self.snapshot()
        with patch.object(i, 'verify_effective', side_effect=m.Refusal('ineffective override')) as verify:
            with self.assertRaisesRegex(m.Refusal, 'ineffective override'):
                self.invoke(i, host)
        verify.assert_called_once()
        self.assertEqual(self.snapshot(), before)
        self.assertTrue(host.active)

    def test_t3_descendant_listener_and_preserved_network_dropin(self):
        i, host = self.fixture('t3')
        network = i.config.parent / 'network.conf'
        network.write_text('[Service]\nEnvironment=T3CODE_HOST=0.0.0.0\n')
        host.dropins = str(network) + ' ' + str(i.config)
        host.listener = '456'
        self.invoke(i, host)
        self.assertEqual(network.read_text(), '[Service]\nEnvironment=T3CODE_HOST=0.0.0.0\n')
        self.assertTrue(host.active)

    def test_retired_migrations_refuse_before_side_effects(self):
        before = self.snapshot()
        for script in ('migrate_legacy_portless_linux.sh', 'migrate_legacy_portless_macos.sh'):
            result = subprocess.run(['bash', str(HERE / script), '--apply'],
                                    text=True, capture_output=True, timeout=5)
            self.assertEqual(result.returncode, 3)
            self.assertEqual(self.snapshot(), before)


if __name__ == '__main__':
    unittest.main()
