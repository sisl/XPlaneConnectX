"""Mock UDP X-Plane server used by the XPlaneConnectX tests.

Listens for RREF subscription requests and — depending on its configuration —
either acknowledges them with a synthetic value, drops the first few requests
for a given DataRef (simulating packet loss), or never responds at all.
"""

import socket
import struct
import threading


class MockXPlane:
    RREF_REQUEST_STRUCT = struct.Struct("<4sxii400s")

    def __init__(self, drop_first_k=None, never_respond=None, response_value=1.23):
        self._drop_first_k = dict(drop_first_k or {})
        self._never_respond = set(never_respond or ())
        self._response_value = response_value

        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("127.0.0.1", 0))
        self.port = self.sock.getsockname()[1]

        self._lock = threading.Lock()
        self._requests = []  # list of (dref, idx, freq)
        self._stop = threading.Event()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self) -> None:
        self.sock.settimeout(0.1)
        while not self._stop.is_set():
            try:
                data, addr = self.sock.recvfrom(16348)
            except socket.timeout:
                continue
            except OSError:
                return
            if len(data) != self.RREF_REQUEST_STRUCT.size:
                continue
            cmd, freq, idx, dref_bytes = self.RREF_REQUEST_STRUCT.unpack(data)
            if cmd != b'RREF':
                continue
            dref = dref_bytes.rstrip(b'\x00').decode('utf-8', errors='replace')

            with self._lock:
                self._requests.append((dref, idx, freq))
                if dref in self._never_respond:
                    continue
                remaining = self._drop_first_k.get(dref, 0)
                if remaining > 0:
                    self._drop_first_k[dref] = remaining - 1
                    continue

            payload = b'RREF\x00' + struct.pack('<if', idx, self._response_value)
            try:
                self.sock.sendto(payload, addr)
            except OSError:
                return

    def received_for(self, dref: str) -> int:
        with self._lock:
            return sum(1 for d, _, _ in self._requests if d == dref)

    def all_requests(self):
        with self._lock:
            return list(self._requests)

    def close(self) -> None:
        self._stop.set()
        try:
            self.sock.close()
        except OSError:
            pass
        self._thread.join(timeout=1.0)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
