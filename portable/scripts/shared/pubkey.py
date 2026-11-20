"""Load the admin public key: from a local file when given, otherwise downloaded from the configured URL."""

import http.client
import socket
import urllib.request

CONNECT_TIMEOUT = 10  # seconds per address before the next one is tried


def _connect(host: str, port: int, timeout: float) -> socket.socket:
    """Connect to host trying IPv4 addresses before IPv6, each with a short timeout.

    Some networks publish AAAA records they cannot reach. urllib then waits the full timeout on each of those
    addresses, one after another, before it reaches an address that works. IPv4 first avoids that stall.
    """
    infos = socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)
    infos.sort(key=lambda info: info[0] != socket.AF_INET)  # stable: IPv4 first, the resolver's order within each family
    last_error: OSError = OSError(f"no address found for {host}")
    for family, kind, proto, _, address in infos:
        sock = socket.socket(family, kind, proto)
        sock.settimeout(min(CONNECT_TIMEOUT, timeout))
        try:
            sock.connect(address)
        except OSError as exc:
            sock.close()
            last_error = exc
            continue
        sock.settimeout(timeout)
        return sock
    raise last_error


class _IPv4FirstHTTPSConnection(http.client.HTTPSConnection):
    def connect(self) -> None:
        if self._tunnel_host:  # through a proxy: the proxy is the host to connect to, so keep urllib's own path
            super().connect()
            return
        self.sock = self._context.wrap_socket(_connect(self.host, self.port, self.timeout), server_hostname=self.host)


class _IPv4FirstHTTPSHandler(urllib.request.HTTPSHandler):
    def https_open(self, req):
        return self.do_open(_IPv4FirstHTTPSConnection, req, context=self._context)


def _open(url: str, timeout: float):
    return urllib.request.build_opener(_IPv4FirstHTTPSHandler).open(url, timeout=timeout)


def load_pubkey(url: str, local_file: str, error_cls: type = RuntimeError) -> str:
    """A local file (ADMIN_PUBKEY_FILE) wins, so the run works offline; a failed download names that escape hatch."""
    if local_file:
        try:
            with open(local_file, encoding="utf-8") as f:
                return f.read()
        except OSError as exc:
            raise error_cls(f"Cannot read admin public key file {local_file}: {exc}") from exc
    try:
        with _open(url, timeout=30) as response:  # downloaded now, installed later
            return response.read().decode("utf-8")
    except (OSError, ValueError) as exc:  # URLError, timeouts and HTTPError are all OSError
        raise error_cls(
            f"Could not download the admin public key from {url}: {exc}\n"
            "Offline? Copy the key to this machine and re-run with ADMIN_PUBKEY_FILE=/path/to/key.pub "
            "(after sudo, like the other overrides).") from exc
