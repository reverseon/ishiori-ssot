"""Tests for the admin public key loader: the IPv4-first connect and the local-file path. Run: python3 -m unittest test_pubkey"""

import socket
import tempfile
import unittest
from unittest import mock

import pubkey

V4 = (socket.AF_INET, socket.SOCK_STREAM, 6, "", ("192.0.2.10", 443))
V6 = (socket.AF_INET6, socket.SOCK_STREAM, 6, "", ("2001:db8::10", 443, 0, 0))


class _FakeSocket:
    """Records each connect() attempt; the addresses in `dead` time out."""

    attempts: list = []
    dead: set = set()

    def __init__(self, family, kind, proto):
        self.family = family

    def settimeout(self, timeout):
        self.timeout = timeout

    def connect(self, address):
        _FakeSocket.attempts.append(address[0])
        if address[0] in _FakeSocket.dead:
            raise TimeoutError("timed out")

    def close(self):
        pass


class ConnectOrderTest(unittest.TestCase):
    def setUp(self):
        _FakeSocket.attempts = []
        _FakeSocket.dead = set()

    def _connect(self, infos):
        with mock.patch.object(pubkey.socket, "getaddrinfo", return_value=infos), \
                mock.patch.object(pubkey.socket, "socket", _FakeSocket):
            return pubkey._connect("example.test", 443, 30)

    def test_ipv4_tried_before_ipv6_even_when_resolver_lists_ipv6_first(self):
        self._connect([V6, V4])
        self.assertEqual(_FakeSocket.attempts, ["192.0.2.10"])

    def test_falls_back_to_ipv6_when_ipv4_fails(self):
        _FakeSocket.dead = {"192.0.2.10"}
        self._connect([V6, V4])
        self.assertEqual(_FakeSocket.attempts, ["192.0.2.10", "2001:db8::10"])

    def test_dead_ipv6_does_not_block_a_working_ipv4(self):
        _FakeSocket.dead = {"2001:db8::10"}
        self._connect([V6, V4])
        self.assertEqual(_FakeSocket.attempts, ["192.0.2.10"])

    def test_every_address_failing_raises(self):
        _FakeSocket.dead = {"192.0.2.10", "2001:db8::10"}
        with self.assertRaises(TimeoutError):
            self._connect([V6, V4])

    def test_connect_attempts_use_the_short_timeout(self):
        seen = []

        class Recording(_FakeSocket):
            def settimeout(self, timeout):
                seen.append(timeout)

        with mock.patch.object(pubkey.socket, "getaddrinfo", return_value=[V4]), \
                mock.patch.object(pubkey.socket, "socket", Recording):
            pubkey._connect("example.test", 443, 30)
        self.assertEqual(seen[0], pubkey.CONNECT_TIMEOUT)
        self.assertEqual(seen[-1], 30)


class LoadPubkeyTest(unittest.TestCase):
    def test_local_file_is_read_without_network(self):
        with tempfile.NamedTemporaryFile("w", delete=False) as f:
            f.write("ssh-ed25519 AAAA test\n")
        with mock.patch.object(pubkey, "_open") as opened:
            self.assertEqual(pubkey.load_pubkey("https://unused", f.name), "ssh-ed25519 AAAA test\n")
        opened.assert_not_called()

    def test_missing_local_file_raises_with_the_path(self):
        with self.assertRaises(RuntimeError) as ctx:
            pubkey.load_pubkey("https://unused", "/nonexistent/key.pub")
        self.assertIn("/nonexistent/key.pub", str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
