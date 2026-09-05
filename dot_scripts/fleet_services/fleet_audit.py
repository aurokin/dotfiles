#!/usr/bin/env python3
"""Bounded read-only fleet inventory. No deployment or repair operations."""
import argparse
import concurrent.futures
from datetime import datetime, timezone
import getpass
import json
import os
from pathlib import Path
import platform

import subprocess
import sys
import tempfile

HOSTS = ("koopa", "metapod", "luma", "haste", "mander", "tortle", "saur", "herb")
PROBE = Path(__file__).with_name("audit_probe.py")


def execute(argv, timeout, input_text=None):
    try:
        p = subprocess.run(argv, input=input_text, text=True, capture_output=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return None, "", "timeout"
    except OSError:
        return None, "", "execution_unavailable"


def transport_error(rc, stderr):
    s = stderr.lower()
    if "host key verification failed" in s or "remote host identification has changed" in s:
        return "host_key_error"
    if "permission denied" in s or "authentication failed" in s:
        return "auth_error"
    if "could not resolve hostname" in s:
        return "dns_error"
    if any(x in s for x in ("connection refused", "no route to host", "network is unreachable")):
        return "offline"
    if "timed out" in s or s == "timeout":
        return "timeout"
    if rc == 255:
        return "ssh_error"
    if rc is None:
        return "execution_error"
    return None


def ssh(host, command, timeout, input_text=None):
    return execute(["ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
                    "-o", "ConnectTimeout=5", "-o", "ConnectionAttempts=1",
                    "-o", "ServerAliveInterval=5", "-o", "ServerAliveCountMax=1",
                    "auro@" + host + ".home.arpa", command], timeout, input_text)


def short_hostname(name):
    return name.lower().split(".")[0]


def audit_host(host, timeout=45, allow_local=True):
    out = {"host": host, "target": "auro@" + host + ".home.arpa", "status": "unknown", "inventory": None}
    local = allow_local and host == "koopa" and short_hostname(platform.node()) == host and getpass.getuser() == "auro"
    out["transport"] = "local" if local else "ssh"
    if local:
        os_name = platform.system()
    else:
        # A single OS discovery command, never a Bash payload on an unknown OS.
        rc, text, err = ssh(host, "uname -s", min(timeout, 10))
        failure = transport_error(rc, err)
        if failure:
            out["status"] = failure
            return out
        os_name = text.strip() if rc == 0 else ""
        if os_name not in ("Linux", "Darwin"):
            rc, text, err = ssh(host, 'powershell.exe -NoProfile -NonInteractive -Command "[Environment]::OSVersion.Platform.ToString(); [Environment]::MachineName"', min(timeout, 10))
            failure = transport_error(rc, err)
            if failure:
                out["status"] = failure
                return out
            lines = text.strip().splitlines()
            if rc == 0 and len(lines) == 2 and lines[0].strip() == "Win32NT":
                out.update(status="wrong_os", identity={"os": "Windows", "hostname": lines[1].strip()})
                out["identity_status"] = "matched" if short_hostname(lines[1].strip()) == host else "mismatch"
            else:
                out["status"] = "os_unknown"
            return out
    out["discovered_os"] = os_name
    if os_name not in ("Darwin", "Linux"):
        out["status"] = "wrong_os"
        return out
    if not local:
        rc, text, err = ssh(host, "hostname; whoami", min(timeout, 10))
        failure = transport_error(rc, err)
        if failure:
            out["status"] = failure
            return out
        lines = text.strip().splitlines()
        if rc != 0 or len(lines) != 2:
            out["status"] = "identity_unknown"
            return out
        out["identity"] = {"hostname": lines[0], "user": lines[1], "os": os_name}
        if short_hostname(lines[0]) != host or lines[1] != "auro":
            out["status"] = "identity_mismatch"
            return out
    payload = PROBE.read_text()
    if local:
        rc, text, err = execute([sys.executable, "-B", "-"], timeout, payload)
    else:
        rc, text, err = ssh(host, "python3 -B -", timeout, payload)
    failure = transport_error(rc, err)
    if failure:
        out["status"] = failure
        return out
    if rc != 0:
        out["status"] = "probe_error"
        return out
    try:
        inventory = json.loads(text)
        identity = inventory["identity"]
        matches = (short_hostname(identity["hostname"]) == host and identity["os"] == os_name and identity["user"] == "auro")
    except (ValueError, KeyError, TypeError, AttributeError):
        out["status"] = "invalid_probe_output"
        return out
    out.update(status="ok" if matches else "identity_mismatch", identity=identity)
    if matches:
        out["inventory"] = inventory
    return out


def controller_http(host, kind):
    url = ("http://verify.%s.home.arpa/" if kind == "portless" else "http://%s.home.arpa:3773/") % host
    rc, text, err = execute([sys.executable, "-B", str(PROBE), "--http", kind, url], 6)
    if rc != 0:
        return {"url": url, "status": "timeout" if err == "timeout" else "probe_error"}
    try:
        result = json.loads(text)
        if not isinstance(result, dict):
            raise ValueError()
        result["url"] = url
        return result
    except ValueError:
        return {"url": url, "status": "invalid_probe_output"}


def audit(hosts, workers=4, timeout=45, allow_local=True):
    started = datetime.now(timezone.utc).isoformat()
    results = {}
    ingress = {host: {} for host in hosts}
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
        jobs: dict = {pool.submit(audit_host, host, timeout, allow_local): (host, None) for host in hosts}
        for host in hosts:
            for kind in ("portless", "t3"):
                jobs[pool.submit(controller_http, host, kind)] = (host, kind)
        for job in concurrent.futures.as_completed(jobs):
            host, kind = jobs[job]
            try:
                result = job.result()
            except Exception:
                # Never emit exception messages with arbitrary remote output or secrets.
                result = {"host": host, "status": "internal_error", "inventory": None}
            if kind:
                ingress[host][kind] = result
            else:
                results[host] = result
    for host in hosts:
        results[host]["controller_http"] = ingress[host]
    return {"schema_version": 1, "started_at": started, "finished_at": datetime.now(timezone.utc).isoformat(),
            "read_only": True, "hosts": [results[h] for h in hosts]}


def save_report(path, text):
    # Atomic, private evidence output. Do not follow an existing report symlink.
    path = Path(path).expanduser()
    fd, temporary = tempfile.mkstemp(prefix=".fleet-audit-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text + "\n")
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hosts", nargs="+", choices=HOSTS, default=list(HOSTS))
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--timeout", type=int, default=45, help="Unix inventory deadline per host, seconds")
    parser.add_argument("--ssh-only", action="store_true", help="Do not use confirmed local koopa")
    parser.add_argument("--report", type=Path, help="Optional atomic private JSON report; parent must exist")
    args = parser.parse_args(argv)
    if not 1 <= args.workers <= 8 or not 1 <= args.timeout <= 120:
        parser.error("workers must be 1..8; timeout must be 1..120")
    report = audit(list(dict.fromkeys(args.hosts)), args.workers, args.timeout, not args.ssh_only)
    text = json.dumps(report, indent=2, sort_keys=True)
    if args.report:
        save_report(args.report, text)
    print(text)
    return 0 if all(h["status"] == "ok" for h in report["hosts"]) else 1


if __name__ == "__main__":
    sys.exit(main())
