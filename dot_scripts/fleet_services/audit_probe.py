#!/usr/bin/env python3
"""Read-only Unix inventory, also sent on stdin over SSH. Stdlib only."""
import concurrent.futures
import getpass
import http.client
import json
import os
from pathlib import Path
import platform
import pwd
import re
import shutil
import subprocess
import time
import urllib.error
import urllib.request


def run(argv, timeout=3):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return None, ""


def version(text):
    # Never return arbitrary program output, which can contain credentials/errors.
    match = re.search(r"(?<![\w.])v?(\d+\.\d+(?:\.\d+)?(?:[-+][a-zA-Z0-9.-]+)?)(?![\w.])", text)
    return match.group(1) if match else None


def artifact(path, execute=False):
    p = Path(path).expanduser()
    out = {"path": str(p), "present": None}
    try:
        p.stat()
        out["present"] = True
    except FileNotFoundError:
        out["present"] = False
        return out
    except OSError:
        out["metadata_status"] = "unavailable"
        return out
    try:
        target = p.resolve()
        st = target.stat()
        out.update(realpath=str(target), uid=st.st_uid, owner=pwd.getpwuid(st.st_uid).pw_name)
        # This is path evidence, not a package-manager ownership assertion.
        out["installation_hint"] = next((name for token, name in (
            ("/mise/", "mise"), ("/.codex/packages/standalone/", "standalone"),
            ("/lib/node_modules/", "npm-global"),
            ("/Cellar/", "homebrew"), ("/auro-services/", "auro-service-runtime"),
            ("/Applications/", "app-bundle")) if token in str(target)), "unknown")
        if execute:
            rc, text = run([str(p), "--version"])
            out.update(version=version(text), version_status="ok" if rc == 0 and version(text) else "unknown")
    except (OSError, KeyError):
        out["metadata_status"] = "unavailable"
    return out


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def classify_http(kind, status, body):
    if kind == "portless":
        # A missing route proves proxy response, not app health. Generic 404 is insufficient.
        text = body.lower()
        if status == 404 and b"portless" in text and any(s in text for s in (b"no route", b"not found", b"no app", b"no matching")):
            return "missing_route_response"
        return "unexpected_response"
    return "http_ok" if status == 200 else "http_error"


def http_probe(kind, port, host_header=None, timeout=3, url=None):
    deadline = time.monotonic() + timeout
    url = url or "http://127.0.0.1:%d/" % port
    request = urllib.request.Request(url, headers={"Host": host_header} if host_header else {})
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    try:
        try:
            response = opener.open(request, timeout=timeout)
        except urllib.error.HTTPError as exc:
            response = exc
        with response:
            status = response.code
            portless_header = response.headers.get("X-Portless") == "1"
            # Portless embeds a large SVG before its missing-route message.
            # Cap both size and elapsed time, including slow trickle responses.
            body = b""
            while kind == "portless" and len(body) < 1024 * 1024:
                if time.monotonic() >= deadline:
                    raise TimeoutError()
                chunk = response.read1(min(16384, 1024 * 1024 - len(body)))
                if not chunk:
                    break
                body += chunk
        classification = classify_http(kind, status, body)
        if kind == "portless" and not portless_header:
            classification = "unexpected_response"
        return {"status": classification, "http_status": status,
                "port": port, "x_portless_1": portless_header}
    except http.client.HTTPException:
        return {"status": "protocol_error", "port": port}
    except (OSError, urllib.error.URLError, TimeoutError):
        return {"status": "unreachable", "port": port}


def service(name, system=False):
    if platform.system() == "Linux":
        argv = ["systemctl"] + ([] if system else ["--user"])
        rc, text = run(argv + ["show", name, "--property=LoadState,ActiveState,SubState,MainPID"])
        if rc != 0:
            return {"status": "unknown"}
        fields = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
        out: dict = {k: v for k, v in fields.items() if k in ("LoadState", "ActiveState", "SubState")}
        out["status"] = "observed"
        pid = fields.get("MainPID", "0")
        if pid.isdigit() and int(pid) > 0:
            out["pid"] = int(pid)
            out["executable"] = artifact("/proc/%s/exe" % pid)
        return out
    if name == "t3code.service":
        return {"status": "desktop_owned_expected", "runtime_owner_verified": False}
    label = {"auro-portless.service": "com.auro.portless", "caddy.service": "com.auro.caddy"}[name]
    domain = "system" if system else "gui/%d" % os.getuid()
    rc, text = run(["launchctl", "print", domain + "/" + label])
    out = {"status": "observed" if rc == 0 else "unknown_or_not_loaded", "label": label}
    for key in ("state", "pid"):
        m = re.search(r"^\s*" + key + r" = ([\w-]+)$", text, re.M)
        if m:
            out[key] = m.group(1)
    return out


def package(path):
    result = artifact(path)
    if result["present"]:
        try:
            with open(path) as f:
                data = json.load(f)
            v = data.get("version")
            result["version"] = version(v) if isinstance(v, str) else None
        except (ValueError, OSError):
            result["version"] = None
    return result


def collect():
    home = Path.home()
    tools = {}
    for name in ("node", "portless", "caddy", "codex", "t3"):
        path = shutil.which(name)
        tools[name] = artifact(path, execute=name in ("node", "caddy", "codex")) if path else {"present": False}
    standalone = [artifact(home / suffix, execute=True) for suffix in (".local/bin/codex", ".codex/bin/codex")]
    services = {name: service(name, system=name == "caddy.service") for name in ("auro-portless.service", "t3code.service", "caddy.service")}
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        t3 = pool.submit(http_probe, "t3", 3773)
        proxy = pool.submit(http_probe, "portless", 1355, "fleet-audit-missing-route.invalid")
        http = {"t3": t3.result(), "portless": proxy.result()}
    packages = {"portless_service": package(home / ".local/share/auro-services/portless/current/node_modules/portless/package.json")}
    stable_node = artifact("/opt/homebrew/opt/node@24/bin/node" if platform.system() == "Darwin" else "/home/linuxbrew/.linuxbrew/opt/node@24/bin/node", execute=True)
    t3_runtime = {"launcher": artifact(home / ".t3/runtime/service-launcher.mjs"), "declared_active_version": None}
    try:
        with (home / ".t3/runtime/service-state.json").open() as f:
            state = json.load(f)
        active = state.get("activeVersion")
        if isinstance(active, str) and re.fullmatch(r"\d+\.\d+\.\d+(?:[-+][a-zA-Z0-9.-]+)?", active):
            t3_runtime["declared_active_version"] = active
            t3_runtime["package"] = package(home / ".t3/runtime/versions" / active / "package.json")
    except (OSError, ValueError, AttributeError):
        pass
    apps = {}
    if platform.system() == "Darwin":
        import plistlib
        for name in ("T3 Code", "T3 Code (Alpha)", "Codex", "ChatGPT"):
            path = Path("/Applications") / (name + ".app/Contents/Info.plist")
            item = artifact(path)
            if item["present"]:
                try:
                    with path.open("rb") as f:
                        data = plistlib.load(f)
                    item["version"] = version(str(data.get("CFBundleShortVersionString", "")))
                except (OSError, ValueError, plistlib.InvalidFileException):
                    item["version"] = None
            apps[name] = item
    return {"identity": {"hostname": platform.node(), "os": platform.system(), "user": getpass.getuser(), "uid": os.getuid()},
            "tools_noninteractive_path": tools, "codex_standalone_candidates": standalone,
            "services": services, "http": http, "packages": packages, "apps": apps,
            "stable_node": stable_node, "t3_runtime": t3_runtime,
            "limitations": ["Noninteractive PATH is not an interactive shell alias inventory.",
                             "Path hints do not establish package ownership; absent candidates do not prove absence.",
                             "HTTP success does not verify T3 authentication, provider sessions or WebSockets.",
                             "No config, process arguments, credentials or response bodies are emitted."]}


if __name__ == "__main__":
    import sys
    if len(sys.argv) == 4 and sys.argv[1] == "--http":
        from urllib.parse import urlsplit
        url = sys.argv[3]
        print(json.dumps(http_probe(sys.argv[2], urlsplit(url).port or 80, url=url)))
    else:
        print(json.dumps(collect()))
