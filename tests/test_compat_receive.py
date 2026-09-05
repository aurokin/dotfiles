"""Receive-loop regressions; no proxies or application services are launched."""
import importlib.util
from pathlib import Path
import socket
import unittest
from unittest.mock import Mock, patch

source = Path(__file__).resolve().parents[1] / 'dot_scripts/compat-portless-isolated.py'
spec = importlib.util.spec_from_file_location('compat', source)
assert spec is not None and spec.loader is not None
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)


class WebSocketReceiveTests(unittest.TestCase):
    def test_handshake_eof_raises(self):
        reader, writer = socket.socketpair()
        try:
            writer.sendall(b'HTTP/1.1 101 incomplete')
            writer.close()
            with self.assertRaises(ConnectionError):
                compat.recv_until(reader, lambda data: b'\r\n\r\n' in data)
        finally:
            reader.close()
            writer.close()

    def test_echo_eof_raises(self):
        reader, writer = socket.socketpair()
        try:
            writer.sendall(b'\x81')
            writer.close()
            with self.assertRaises(ConnectionError):
                compat.recv_until(reader, lambda data: len(data) >= 17)
        finally:
            reader.close()
            writer.close()

    def test_fragmented_handshake(self):
        peer = Mock()
        peer.recv.side_effect = [b'HTTP/1.1 101\r\n', b'\r\n']
        self.assertEqual(compat.recv_until(peer, lambda data: b'\r\n\r\n' in data),
                         b'HTTP/1.1 101\r\n\r\n')

    def test_size_limit(self):
        peer = Mock()
        peer.recv.return_value = b'x' * 8
        with self.assertRaises(ValueError):
            compat.recv_until(peer, lambda data: False, limit=8)
        peer.recv.assert_called_once()

    def test_deadline_bounds_slow_drip(self):
        peer = Mock()
        peer.recv.return_value = b'x'
        with patch.object(compat.time, 'monotonic', side_effect=[0, 0, 4]):
            with self.assertRaises(TimeoutError):
                compat.recv_until(peer, lambda data: False, timeout=3)
        peer.recv.assert_called_once()


if __name__ == '__main__':
    unittest.main()
