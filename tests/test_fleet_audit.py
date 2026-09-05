"""No real SSH or installed CLI execution in unit tests."""
import importlib.util
import json
from pathlib import Path
import stat
import socketserver
import subprocess
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[1] / "dot_scripts/fleet_services"


def load(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / (name + ".py"))
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


audit = load("fleet_audit")
probe = load("audit_probe")


class AuditTests(unittest.TestCase):
    def test_malformed_http_is_a_local_observation_not_host_failure(self):
        for response in (b'NOT-HTTP secret\r\n\r\n',
                         b'HTTP/1.1 404 Not Found\r\nTransfer-Encoding: chunked\r\n\r\nnot-hex\r\n'):
            class Handler(socketserver.BaseRequestHandler):
                def handle(self):
                    self.request.settimeout(2)
                    self.request.recv(4096)
                    self.request.sendall(response)
            with self.subTest(response=response), socketserver.TCPServer(('127.0.0.1', 0), Handler) as server:
                worker = threading.Thread(target=server.handle_request, daemon=True)
                worker.start()
                result = probe.http_probe('portless', server.server_address[1])
                worker.join(timeout=3)
                self.assertFalse(worker.is_alive())
                self.assertEqual(result, {'status': 'protocol_error', 'port': server.server_address[1]})
                self.assertNotIn('secret', json.dumps(result))

    def test_transport_categories(self):
        for message, expected in (("Permission denied (publickey)", "auth_error"),
                                  ("Host key verification failed", "host_key_error"),
                                  ("REMOTE HOST IDENTIFICATION HAS CHANGED", "host_key_error"),
                                  ("Could not resolve hostname x", "dns_error"),
                                  ("Connection refused", "offline"),
                                  ("Connection timed out", "timeout"),
                                  ("other", "ssh_error")):
            with self.subTest(message=message):
                self.assertEqual(audit.transport_error(255, message), expected)

    def test_timeout_does_not_emit_command(self):
        with patch.object(audit.subprocess, "run", side_effect=subprocess.TimeoutExpired("secret", 1)):
            self.assertEqual(audit.execute(["secret"], 1), (None, "", "timeout"))

    def test_ssh_security(self):
        with patch.object(audit, "execute", return_value=(0, "", "")) as call:
            audit.ssh("haste", "uname -s", 8)
        args = call.call_args.args[0]
        self.assertIn("StrictHostKeyChecking=yes", args)
        self.assertIn("BatchMode=yes", args)
        self.assertIn("ConnectionAttempts=1", args)
        self.assertIn("auro@haste.home.arpa", args)
        self.assertNotIn("StrictHostKeyChecking=no", args)

    def test_windows_never_gets_unix_payload(self):
        with patch.object(audit, "ssh", side_effect=[(1, "", "not recognized"), (0, "Win32NT\nDESKTOP-X\n", "")]) as call:
            result = audit.audit_host("haste", allow_local=False)
        self.assertEqual(result["status"], "wrong_os")
        self.assertEqual(result["identity_status"], "mismatch")
        self.assertEqual(call.call_count, 2)
        self.assertNotIn("python3", str(call.call_args_list))

    def test_auth_stops_discovery(self):
        with patch.object(audit, "ssh", return_value=(255, "", "Permission denied SECRET")) as call:
            result = audit.audit_host("haste", allow_local=False)
        self.assertEqual(result["status"], "auth_error")
        self.assertEqual(call.call_count, 1)
        self.assertNotIn("SECRET", json.dumps(result))

    def test_identity_stops_inventory(self):
        with patch.object(audit, "ssh", side_effect=[(0, "Linux\n", ""), (0, "other\nauro\n", "")]) as call:
            result = audit.audit_host("herb", allow_local=False)
        self.assertEqual(result["status"], "identity_mismatch")
        self.assertEqual(call.call_count, 2)

    def test_success_and_invalid_inventory(self):
        identity = {"hostname": "herb", "user": "auro", "os": "Linux"}
        for body, expected in ((json.dumps({"identity": identity, "http": {"t3": {"status": "unreachable"}}}), "ok"), ("SECRET malformed", "invalid_probe_output")):
            with patch.object(audit, "ssh", side_effect=[(0, "Linux\n", ""), (0, "herb\nauro\n", ""), (0, body, "")]):
                result = audit.audit_host("herb", allow_local=False)
            self.assertEqual(result["status"], expected)
            self.assertNotIn("SECRET", json.dumps(result))

    def test_local_requires_user_and_host(self):
        with patch.object(audit.platform, "node", return_value="koopa.home.arpa"), patch.object(audit.getpass, "getuser", return_value="other"), patch.object(audit, "ssh", return_value=(255, "", "Connection refused")) as call:
            result = audit.audit_host("koopa")
        self.assertEqual(result["transport"], "ssh")
        self.assertEqual(call.call_count, 1)

    def test_fleet_failure_isolated_and_parallel_bounded(self):
        lock = threading.Lock()
        active = peak = 0
        def work(host, *args):
            nonlocal active, peak
            with lock:
                active += 1
                peak = max(peak, active)
            time.sleep(.02)
            with lock:
                active -= 1
            if host == "luma":
                raise RuntimeError("SECRET")
            return {"host": host, "status": "ok"}
        with patch.object(audit, "audit_host", side_effect=work), patch.object(audit, "controller_http", return_value={"status": "unreachable"}):
            report = audit.audit(list(audit.HOSTS), workers=2)
        self.assertEqual(len(report["hosts"]), 8)
        self.assertEqual([h["host"] for h in report["hosts"]], list(audit.HOSTS))
        self.assertEqual(peak, 2)
        self.assertEqual(report["hosts"][2]["status"], "internal_error")
        self.assertIn("+00:00", report["started_at"])
        self.assertNotIn("SECRET", json.dumps(report))

    def test_private_report_replaces_symlink_not_target(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "target"
            target.write_text("keep")
            report = Path(directory) / "report.json"
            report.symlink_to(target)
            audit.save_report(report, "{}")
            self.assertEqual(target.read_text(), "keep")
            self.assertEqual(json.loads(report.read_text()), {})
            self.assertEqual(stat.S_IMODE(report.stat().st_mode), 0o600)

    def test_http_classification(self):
        self.assertEqual(probe.classify_http("t3", 200, b""), "http_ok")
        self.assertEqual(probe.classify_http("t3", 401, b""), "http_error")
        self.assertEqual(probe.classify_http("portless", 404, b"No app registered for test; portless test command"), "missing_route_response")
        self.assertEqual(probe.classify_http("portless", 404, b"generic not found"), "unexpected_response")
        self.assertEqual(probe.classify_http("portless", 200, b"portless"), "unexpected_response")

    def test_http_real_local_fixture_no_redirect_or_body_leak(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(302)
                self.send_header("Location", "http://example.invalid/SECRET")
                self.end_headers()
                self.wfile.write(b"SECRET")
            def log_message(self, format, *args):
                pass
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            result = probe.http_probe("t3", server.server_port)
            self.assertEqual(result["http_status"], 302)
            self.assertEqual(result["status"], "http_error")
            self.assertNotIn("SECRET", json.dumps(result))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_version_whitelist_and_symlink_owner(self):
        self.assertEqual(probe.version("codex-cli 0.153.2"), "0.153.2")
        self.assertIsNone(probe.version("SECRET failed"))
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / ".codex/packages/standalone/releases/1.2.3/bin/codex"
            binary.parent.mkdir(parents=True)
            binary.write_text("")
            link = Path(directory) / "codex"
            link.symlink_to(binary)
            result = probe.artifact(link)
            self.assertEqual(result["realpath"], str(binary.resolve()))
            self.assertEqual(result["installation_hint"], "standalone")
            self.assertIn("owner", result)

    def test_service_emits_only_allowlisted_fields(self):
        text = "LoadState=loaded\nActiveState=active\nSubState=running\nMainPID=0\nEnvironment=SECRET\nExecStart=SECRET\n"
        with patch.object(probe.platform, "system", return_value="Linux"), patch.object(probe, "run", return_value=(0, text)):
            result = probe.service("t3code.service")
        self.assertEqual(result["ActiveState"], "active")
        self.assertNotIn("SECRET", json.dumps(result))


if __name__ == "__main__":
    unittest.main()
