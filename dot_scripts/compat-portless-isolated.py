#!/usr/bin/env python3
"""Real, loopback-only Portless 0.15.6 compatibility checks. No live service commands.
Usage: python3 dot_scripts/compat-portless-isolated.py --report /tmp/report.json [--astro]
--astro installs astro@5.13.5 and ws@8.18.3 in the disposable fixture, never globally.
Direct dependency versions are pinned; npm resolves their transitive dependencies.
"""
import argparse
import base64
import hashlib
import http.client
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import socket
import subprocess
import tempfile
import time

SYSTEM = platform.system()
NODE = {'Darwin': '/opt/homebrew/opt/node@24/bin/node',
        'Linux': '/home/linuxbrew/.linuxbrew/opt/node@24/bin/node'}.get(SYSTEM)
LSOF = shutil.which('lsof') or ''
LSOF_WARNINGS = []
PACKAGE = Path.home() / '.local/share/auro-services/portless/current/node_modules/portless'
SERVER = r'''
const http=require('node:http'), crypto=require('node:crypto'), fs=require('node:fs');
fs.writeFileSync(process.env.PID_FILE,String(process.pid));
const s=http.createServer((q,r)=>{if(q.url==='/exit'){r.end('bye');setTimeout(()=>s.close(()=>process.exit(0)),50);return;}r.setHeader('content-type','application/json');r.end(JSON.stringify({pid:process.pid,host:q.headers.host,url:process.env.PORTLESS_URL,port:process.env.PORT}));});
s.on('upgrade',(q,s)=>{const key=crypto.createHash('sha1').update(q.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');s.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+key+'\r\n\r\n');s.on('data',b=>{const n=b[1]&127;if(n>125||b.length<6+n)return s.destroy();const p=Buffer.from(b.subarray(6,6+n));for(let i=0;i<n;i++)p[i]^=b[2+i%4];s.write(Buffer.concat([Buffer.from([129,n]),p]));});});
s.listen(Number(process.env.PORT),'127.0.0.1');
'''


def wait(fn, timeout=12):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = fn()
            if value:
                return value
        except (OSError, ValueError, http.client.HTTPException):
            pass
        time.sleep(.1)
    raise TimeoutError('condition not met')


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False


def lsof_output(arguments):
    result = subprocess.run([LSOF] + arguments, capture_output=True, text=True, timeout=10)
    if result.returncode == 0 and result.stdout.strip():
        if result.stderr.strip():
            LSOF_WARNINGS.append({'arguments': arguments, 'stderr': result.stderr})
        return result.stdout.strip()
    if result.returncode == 1 and not result.stdout.strip() and not result.stderr.strip():
        return ''
    raise RuntimeError(f'lsof result uncertain: rc={result.returncode}, stderr={result.stderr!r}, stdout={result.stdout!r}')


def recv_until(sock, complete, limit=65536, timeout=3):
    """Bound EOF, oversized responses, and slow-drip peers as well as silence."""
    deadline = time.monotonic() + timeout
    data = b''
    while not complete(data):
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('WebSocket receive deadline exceeded')
        if len(data) >= limit:
            raise ValueError('WebSocket response exceeded size limit')
        sock.settimeout(remaining)
        chunk = sock.recv(min(4096, limit - len(data)))
        if not chunk:
            raise ConnectionError('WebSocket closed before completing response')
        data += chunk
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--report', required=True)
    parser.add_argument('--astro', action='store_true')
    args = parser.parse_args()
    if not NODE or not os.access(NODE, os.X_OK) or not LSOF:
        raise SystemExit('Requires macOS/Linux, stable Homebrew Node 24, and lsof on PATH')
    # Review installed source before invoking any CLI, including help.
    source = (PACKAGE / 'dist/cli.js').read_text()
    version = json.loads((PACKAGE / 'package.json').read_text())['version']
    if version != '0.15.6' or 'PORTLESS_SYNC_HOSTS' not in source or 'PORTLESS_STATE_DIR' not in source:
        raise SystemExit('Unsupported installed source: review isolation controls first')
    report = {'started_at_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'version': version,
              'platform': SYSTEM, 'hostname': socket.gethostname(), 'node_path': NODE, 'lsof_path': LSOF,
              'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'results': []}
    root = Path(tempfile.mkdtemp(prefix='compat-portless-'))
    report['temporary_root'] = str(root)
    state = root / 'state'
    state.mkdir()
    processes, children, ports, logs = [], set(), [], []
    before_hosts = Path('/etc/hosts').read_bytes()
    # Do not inherit credentials, NODE_OPTIONS, npm config, or live XDG state.
    env = {k: v for k, v in os.environ.items() if k in ('LANG', 'LC_ALL', 'TZ')}
    env.update(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(root / 'config'), CI='1',
               PORTLESS_STATE_DIR=str(state), PORTLESS_HTTPS='0', PORTLESS_LAN='0',
               PORTLESS_SYNC_HOSTS='0', PORTLESS_TLD='compat.invalid', PORTLESS_WILDCARD='0',
               PATH=str(Path(NODE).parent) + ':/usr/bin:/bin:/usr/sbin:/sbin', ASTRO_TELEMETRY_DISABLED='1')
    Path(env['HOME']).mkdir()
    env.update(XDG_CACHE_HOME=str(root / 'cache'), XDG_DATA_HOME=str(root / 'data'),
               XDG_STATE_HOME=str(root / 'xdg-state'), TMPDIR=str(root),
               NPM_CONFIG_USERCONFIG=str(root / 'empty-npmrc'),
               NPM_CONFIG_GLOBALCONFIG=str(root / 'empty-global-npmrc'))
    report['node'] = subprocess.check_output([NODE, '--version'], env=env, text=True).strip()
    cli = [NODE, str(PACKAGE / 'dist/cli.js')]

    def record(name, ok, detail):
        report['results'].append({'name': name, 'status': 'pass' if ok else 'fail', 'detail': detail})

    def port():
        with socket.socket() as s:
            s.bind(('127.0.0.1', 0))
            p = s.getsockname()[1]
        if p < 10000 or p in ports:
            return port()
        ports.append(p)
        return p

    proxy_port = port()
    env['PORTLESS_PORT'] = str(proxy_port)

    def start(command, label, cwd=root, extra=None):
        f = (root / (label + '.log')).open('w')
        logs.append(f)
        p = subprocess.Popen(command, cwd=cwd, env=env | (extra or {}), stdout=f,
                             stderr=subprocess.STDOUT, start_new_session=True)
        processes.append(p)
        return p

    def call(arguments):
        return subprocess.run(cli + arguments, cwd=root, env=env, capture_output=True, text=True, timeout=20)

    def request(host, path='/', target=proxy_port):
        c = http.client.HTTPConnection('127.0.0.1', target, timeout=2)
        try:
            c.request('GET', path, headers={'Host': host})
            r = c.getresponse()
            return r.status, r.read().decode()
        finally:
            c.close()

    def routes():
        return json.loads((state / 'routes.json').read_text())

    def launch(name):
        app_port = port()
        pidfile = root / (name + '.pid')
        p = start(cli + [name, '--app-port', str(app_port), NODE, str(root / 'server.cjs')], name,
                  extra={'PID_FILE': str(pidfile)})
        wait(lambda: pidfile.exists())
        child = int(pidfile.read_text())
        children.add(child)
        host = name + '.compat.invalid'
        wait(lambda: request(host)[0] == 200)
        return p, child, host, app_port

    def sockets(pid):
        # A reaped PID cannot own sockets. Linux lsof -p for a missing PID may
        # otherwise emit unrelated inaccessible snap mount warnings with rc=1.
        if not alive(pid):
            return ''
        return lsof_output(['-nP', '-a', '-p', str(pid), '-iTCP', '-sTCP:LISTEN'])

    try:
        (root / 'server.cjs').write_text(SERVER)
        proxy = start(cli + ['proxy', 'start', '--foreground', '--no-tls', '--port', str(proxy_port), '--tld', 'compat.invalid'], 'proxy')
        wait(lambda: request('missing.compat.invalid')[0] == 404)
        binding = sockets(proxy.pid)
        record('proxy_loopback_binding', bool(binding) and '*:' not in binding and '127.0.0.1:' in binding, binding)
        p, child, host, app_port = launch('normal')
        status, body = request(host)
        data = json.loads(body)
        record('http_host_and_environment', status == 200 and data['host'] == host and data['port'] == str(app_port) and host in data['url'], data)
        binding = sockets(child)
        record('backend_loopback_binding', '127.0.0.1:' in binding and '*:' not in binding, binding)
        with socket.create_connection(('127.0.0.1', proxy_port), timeout=3) as ws:
            key = base64.b64encode(os.urandom(16)).decode()
            ws.sendall(f'GET /ws HTTP/1.1\r\nHost: {host}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n'.encode())
            header = recv_until(ws, lambda data: b'\r\n\r\n' in data)
            payload, mask = b'compat-real-echo', os.urandom(4)
            ws.sendall(bytes([129, 128 | len(payload)]) + mask + bytes(x ^ mask[i % 4] for i, x in enumerate(payload)))
            response = recv_until(ws, lambda data: len(data) >= len(payload) + 2)
            accept = base64.b64encode(hashlib.sha1((key + '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').encode()).digest())
            record('websocket_upgrade_and_echo', b'101' in header and accept in header and response[2:] == payload, {'handshake': header.decode(), 'echo': response[2:].decode()})
        request(host, '/exit')
        p.wait(timeout=12)
        wait(lambda: not alive(child) and not any(r['hostname'] == host for r in routes()) and request(host)[0] == 404)
        record('normal_child_exit_cleanup', request(host)[0] == 404 and not sockets(child), {'wrapper_exit': p.returncode, 'child': child, 'routes': routes()})
        p, child, host, app_port = launch('signal')
        p.send_signal(signal.SIGTERM)
        p.wait(timeout=12)
        wait(lambda: not alive(child) and not any(r['hostname'] == host for r in routes()) and request(host)[0] == 404)
        record('sigterm_tree_cleanup', request(host)[0] == 404 and not sockets(child), {'wrapper_exit': p.returncode, 'child': child})
        p, child, host, app_port = launch('abrupt')
        p.kill()
        p.wait(timeout=5)
        time.sleep(1)
        record('sigkill_automatic_cleanup', not alive(child) and request(host)[0] == 404 and not any(r['hostname'] == host for r in routes()), {'child_alive': alive(child), 'http_status': request(host)[0], 'raw_routes': routes()})
        # Never invoke prune: it can signal listeners by port. Kill only our recorded child.
        if alive(child):
            os.kill(child, signal.SIGTERM)
        wait(lambda: not alive(child))
        # Alias mutation triggers RouteStore's locked stale-route persistence.
        alias_port = port()
        pidfile = root / 'alias.pid'
        backend = start([NODE, str(root / 'server.cjs')], 'alias-backend', extra={'PORT': str(alias_port), 'PID_FILE': str(pidfile)})
        wait(lambda: pidfile.exists())
        children.add(int(pidfile.read_text()))
        result = call(['alias', 'external', str(alias_port)])
        wait(lambda: request('external.compat.invalid')[0] == 200)
        record('static_alias_http', result.returncode == 0 and any(r['hostname'] == 'external.compat.invalid' and r['pid'] == 0 for r in routes()), routes())
        record('stale_route_cleanup_on_mutation', not any(r['hostname'] == host for r in routes()) and request(host)[0] == 404, routes())
        result = call(['alias', '--remove', 'external'])
        wait(lambda: request('external.compat.invalid')[0] == 404)
        record('static_alias_remove_preserves_external_backend', result.returncode == 0 and backend.poll() is None and request('localhost', target=alias_port)[0] == 200, routes())
        if args.astro:
            astro_test(root, env, cli, start, port, request, wait, record, report, children, NODE)
        else:
            report['results'].append({'name': 'astro_worktree_hmr', 'status': 'deferred', 'detail': 'Run with --astro for pinned disposable installation.'})
    except Exception as exc:
        record('runner_exception', False, repr(exc))
    finally:
        # Only sessions we started, plus child PIDs learned from our fixture files.
        cleanup_errors = []
        for p in reversed(processes):
            try:
                if p.poll() is None:
                    os.killpg(p.pid, signal.SIGTERM)
                    try:
                        p.wait(timeout=8)
                    except subprocess.TimeoutExpired:
                        os.killpg(p.pid, signal.SIGKILL)
                        p.wait(timeout=5)
            except Exception as exc:
                cleanup_errors.append(f'process {p.pid}: {exc!r}')
        for child in children:
            try:
                if alive(child):
                    os.kill(child, signal.SIGTERM)
                    wait(lambda: not alive(child), timeout=5)
            except Exception as exc:
                cleanup_errors.append(f'child {child}: {exc!r}')
        for f in logs:
            try:
                f.close()
            except Exception as exc:
                cleanup_errors.append(f'log close: {exc!r}')
        report['logs'] = {}
        for logfile in root.glob('*.log'):
            try:
                report['logs'][logfile.name] = logfile.read_text()
            except Exception as exc:
                cleanup_errors.append(f'log read {logfile.name}: {exc!r}')
        report['owned_pids'] = sorted({p.pid for p in processes} | children)
        report['owned_ports'] = ports
        leftovers = {}
        for pid in report['owned_pids']:
            try:
                if alive(pid):
                    leftovers[str(pid)] = sockets(pid)
            except Exception as exc:
                cleanup_errors.append(f'pid probe {pid}: {exc!r}')
        listening = {}
        for owned_port in ports:
            try:
                out = lsof_output(['-nP', '-iTCP:' + str(owned_port), '-sTCP:LISTEN'])
                if out:
                    listening[str(owned_port)] = out
            except Exception as exc:
                cleanup_errors.append(f'port probe {owned_port}: {exc!r}')
        record('final_owned_pid_and_listener_cleanup', not leftovers and not listening and not cleanup_errors,
               {'surviving_pids': leftovers, 'listeners': listening, 'errors': cleanup_errors})
        try:
            final_routes = routes() if (state / 'routes.json').exists() else []
            record('final_routes_empty', not final_routes, final_routes)
            record('hosts_file_unchanged', Path('/etc/hosts').read_bytes() == before_hosts, 'Compared exact bytes before and after.')
        except Exception as exc:
            cleanup_errors.append(f'final state probe: {exc!r}')
            record('final_state_probe', False, repr(exc))
        report['results'].append({'name': 'lan_vpn_tls_real_application_corpus', 'status': 'deferred', 'detail': 'Loopback fixture only on the reported platform; no live-service operations or real repository migration gate.'})
        report['results'].append({'name': 'browser_rendering_and_framework_flag_injection', 'status': 'deferred', 'detail': 'HMR protocol and subsequent HTML were exercised, not browser rendering. Astro used explicit loopback host and high port. Automatic framework flag injection, Next, Webmux, and multi-app repositories were not tested.'})
        if not leftovers and not listening and not cleanup_errors:
            try:
                shutil.rmtree(root)
            except Exception as exc:
                record('temporary_directory_removal_error', False, repr(exc))
        record('temporary_directory_removed', not root.exists(), str(root))
        report['lsof_warnings'] = LSOF_WARNINGS
        Path(args.report).parent.mkdir(parents=True, exist_ok=True)
        Path(args.report).write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps({'report': args.report, 'results': report['results']}, indent=2))
    return int(any(r['status'] == 'fail' for r in report['results']))


def astro_test(root, env, cli, start, port, request, wait, record, report, children, node):
    fixture = root / 'astro-main'
    fixture.mkdir()
    def run(command, cwd=fixture):
        return subprocess.run(command, cwd=cwd, env=env, capture_output=True, text=True, timeout=150)
    (fixture / 'package.json').write_text(json.dumps({'name': 'compat-astro', 'version': '0.0.0', 'type': 'module', 'dependencies': {'astro': '5.13.5', 'ws': '8.18.3'}}))
    result = run([str(Path(node).parent / 'npm'), 'install', '--ignore-scripts', '--no-audit', '--no-fund'])
    if result.returncode:
        report['results'].append({'name': 'astro_worktree_hmr', 'status': 'deferred', 'detail': result.stderr[-3000:]})
        return
    run(['/usr/bin/git', 'init'])
    linked = root / 'astro-linked'
    result = run(['/usr/bin/git', 'worktree', 'add', '--orphan', '-b', 'compat-linked', str(linked)])
    if result.returncode:
        report['results'].append({'name': 'astro_linked_worktree', 'status': 'deferred', 'detail': result.stderr})
        return
    shutil.copy(fixture / 'package.json', linked / 'package.json')
    (linked / 'node_modules').symlink_to(fixture / 'node_modules', target_is_directory=True)
    (linked / 'src/pages').mkdir(parents=True)
    page = linked / 'src/pages/index.astro'
    page.write_text('<h1>compat-before</h1>')
    (linked / 'astro.config.mjs').write_text("import {defineConfig} from 'astro/config'; export default defineConfig({server:{host:'127.0.0.1'},vite:{server:{allowedHosts:['.compat.invalid']}}});")
    astro_port = port()
    p = start(cli + ['run', '--name', 'compat-astro', '--app-port', str(astro_port), str(linked / 'node_modules/.bin/astro'), 'dev', '--host', '127.0.0.1', '--port', str(astro_port)], 'astro', cwd=linked)
    hostname = 'compat-linked.compat-astro.compat.invalid'
    wait(lambda: request(hostname)[0] == 200, timeout=45)
    status, body = request(hostname)
    owners = lsof_output(['-t', '-a', '-iTCP:' + str(astro_port), '-sTCP:LISTEN']).split()
    if not owners:
        raise RuntimeError('Astro listener ownership unverified')
    # Require each discovered listener to descend from our wrapper before recording ownership.
    for owner in map(int, owners):
        ancestor = owner
        for _ in range(20):
            if ancestor == p.pid:
                children.add(owner)
                break
            ancestor = int(subprocess.check_output(['/bin/ps', '-o', 'ppid=', '-p', str(ancestor)], text=True).strip())
            if ancestor <= 1:
                raise RuntimeError('Astro port listener is not our descendant')
        else:
            raise RuntimeError('Astro ancestry depth exceeded')
    record('astro_linked_worktree_http', status == 200 and 'compat-before' in body, {'hostname': hostname, 'port': astro_port, 'explicit_flags': True})
    # Use installed Vite ws package for actual HMR protocol, not a mocked upgrade.
    client = root / 'hmr-client.mjs'
    ws_path = next((fixture / 'node_modules').glob('ws/index.js'), None)
    if not ws_path:
        report['results'].append({'name': 'astro_hmr_websocket', 'status': 'deferred', 'detail': 'Installed ws module missing.'})
    else:
        client.write_text("import WebSocket from " + json.dumps(str(ws_path)) + ";import fs from 'node:fs';const w=new WebSocket(process.argv[2],'vite-hmr',{headers:{Host:process.argv[3]}});let connected=false;const t=setTimeout(()=>process.exit(2),15000);w.on('message',b=>{console.log(String(b));const m=JSON.parse(String(b));if(m.type==='connected'){connected=true;setTimeout(()=>fs.writeFileSync(process.argv[4],'<h1>compat-after</h1>'),200);}if(connected&&(m.type==='full-reload'||m.type==='update')){clearTimeout(t);w.close();}});w.on('error',e=>{console.error(e);process.exit(3)});")
        result = run([node, str(client), 'ws://127.0.0.1:' + env['PORTLESS_PORT'] + '/', hostname, str(page)])
        record('astro_hmr_websocket', result.returncode == 0 and 'connected' in result.stdout and ('full-reload' in result.stdout or 'update' in result.stdout), {'stdout': result.stdout, 'stderr': result.stderr, 'exit': result.returncode})
        record('astro_updated_http', 'compat-after' in request(hostname)[1], request(hostname)[0])
    p.send_signal(signal.SIGTERM)
    p.wait(timeout=15)
    wait(lambda: request(hostname)[0] == 404)
    record('astro_sigterm_route_cleanup', True, {'wrapper_exit': p.returncode})


if __name__ == '__main__':
    raise SystemExit(main())
