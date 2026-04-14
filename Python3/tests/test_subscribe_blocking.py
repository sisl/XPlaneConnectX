"""Tests for the blocking / retrying behavior of XPlaneConnectX.subscribeDREFs.

Run directly with:
    python Python3/tests/test_subscribe_blocking.py

Uses only the standard library and a lightweight mock UDP server.
"""

import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
PARENT = os.path.dirname(HERE)
sys.path.insert(0, PARENT)
sys.path.insert(0, HERE)

from XPlaneConnectX import XPlaneConnectX  # noqa: E402
from mock_xplane import MockXPlane  # noqa: E402


def test_retry_recovers():
    with MockXPlane(drop_first_k={'dref/a': 2, 'dref/b': 1}) as mock:
        xpc = XPlaneConnectX(ip='127.0.0.1', port=mock.port)
        xpc.subscribeDREFs(
            [('dref/a', 1), ('dref/b', 1), ('dref/c', 1)],
            timeout=5.0,
            retry_interval=0.3,
        )

        for name in ('dref/a', 'dref/b', 'dref/c'):
            assert xpc.current_dref_values[name]['value'] is not None, \
                f"no value received for {name}"

        assert mock.received_for('dref/a') >= 3, \
            f"expected >=3 requests for dref/a, got {mock.received_for('dref/a')}"
        assert mock.received_for('dref/b') >= 2, \
            f"expected >=2 requests for dref/b, got {mock.received_for('dref/b')}"
        assert mock.received_for('dref/c') >= 1, \
            f"expected >=1 request for dref/c, got {mock.received_for('dref/c')}"


def test_missing_dref_raises():
    with MockXPlane(never_respond={'dref/bad'}) as mock:
        xpc = XPlaneConnectX(ip='127.0.0.1', port=mock.port)
        timeout = 1.0
        retry_interval = 0.3

        start = time.monotonic()
        raised = None
        try:
            xpc.subscribeDREFs(
                [('dref/ok', 1), ('dref/bad', 1)],
                timeout=timeout,
                retry_interval=retry_interval,
            )
        except TimeoutError as e:
            raised = e
        elapsed = time.monotonic() - start

        assert raised is not None, "expected TimeoutError to be raised"
        msg = str(raised)
        assert 'dref/bad' in msg, f"error should name dref/bad, got: {msg!r}"
        assert 'dref/ok' not in msg, f"error should not name dref/ok, got: {msg!r}"

        assert timeout <= elapsed <= timeout + retry_interval + 0.5, \
            f"elapsed {elapsed:.3f}s outside expected range"

        # the responsive dref still should have landed
        assert xpc.current_dref_values['dref/ok']['value'] is not None, \
            "dref/ok should have received a value before the timeout"


def test_fast_return_happy_path():
    with MockXPlane() as mock:
        xpc = XPlaneConnectX(ip='127.0.0.1', port=mock.port)
        drefs = [('dref/x', 1), ('dref/y', 1), ('dref/z', 1)]

        start = time.monotonic()
        xpc.subscribeDREFs(drefs, timeout=5.0, retry_interval=0.5)
        elapsed = time.monotonic() - start

        assert elapsed < 0.3, f"happy-path subscribe took {elapsed:.3f}s, expected <0.3s"
        for name, _ in drefs:
            assert xpc.current_dref_values[name]['value'] is not None, \
                f"no value for {name}"
            count = mock.received_for(name)
            assert count == 1, f"expected exactly 1 request for {name}, got {count}"


TESTS = [
    test_retry_recovers,
    test_missing_dref_raises,
    test_fast_return_happy_path,
]


def main() -> int:
    failures = 0
    for t in TESTS:
        try:
            t()
        except Exception:
            failures += 1
            print(f"FAIL {t.__name__}")
            traceback.print_exc()
        else:
            print(f"OK   {t.__name__}")
    if failures:
        print(f"\n{failures}/{len(TESTS)} tests failed")
        return 1
    print(f"\nAll {len(TESTS)} tests passed")
    return 0


if __name__ == '__main__':
    sys.exit(main())
