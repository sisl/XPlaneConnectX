"""End-to-end tests for XPlaneConnectX against a running X-Plane instance.

Run with:
    python3 Python3/tests/test_live_xplane.py

Environment variables:
    XPLANE_HOST (default 127.0.0.1)
    XPLANE_PORT (default 49000)

The test suite first probes X-Plane; if it doesn't respond within ~2 seconds
all tests are skipped with a non-failing exit code so this file is safe to
run in environments without a simulator.

What the tests will do (all reversible): briefly toggle landing lights,
pause and unpause the simulator, shift the aircraft position by a fraction
of a degree and then restore it, apply zero-ish control inputs and restore
them, and subscribe/record a handful of read-only DataRefs. No flight reset
is issued and no destructive commands are sent.
"""

import os
import struct
import socket
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
PARENT = os.path.dirname(HERE)
sys.path.insert(0, PARENT)

from XPlaneConnectX import XPlaneConnectX  # noqa: E402

XPLANE_HOST = os.environ.get('XPLANE_HOST', '127.0.0.1')
XPLANE_PORT = int(os.environ.get('XPLANE_PORT', '49000'))


def probe_xplane(timeout: float = 2.0) -> bool:
    """Send a one-shot RREF for a known DataRef; return True if X-Plane answers."""
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.settimeout(timeout)
    dref = "sim/time/total_running_time_sec"
    idx = 12345
    try:
        sub = struct.pack("<4sxii400s", b'RREF', 1, idx, dref.encode('utf-8'))
        sock.sendto(sub, (XPLANE_HOST, XPLANE_PORT))
        data, _ = sock.recvfrom(16348)
        return data[:4] == b'RREF'
    except (socket.timeout, OSError):
        return False
    finally:
        try:
            unsub = struct.pack("<4sxii400s", b'RREF', 0, idx, dref.encode('utf-8'))
            sock.sendto(unsub, (XPLANE_HOST, XPLANE_PORT))
        except OSError:
            pass
        sock.close()


def new_client() -> XPlaneConnectX:
    return XPlaneConnectX(ip=XPLANE_HOST, port=XPLANE_PORT)


# ---------- synchronous method tests ----------

def test_getDREF_returns_sensible_value():
    xpc = new_client()
    v = xpc.getDREF("sim/time/total_running_time_sec")
    assert isinstance(v, float), f"expected float, got {type(v).__name__}"
    assert v > 0, f"total_running_time_sec should be > 0, got {v}"


def test_sendDREF_then_getDREF_roundtrip():
    xpc = new_client()
    dref = "sim/cockpit/electrical/landing_lights_on"
    original = xpc.getDREF(dref)
    try:
        target = 0.0 if original >= 0.5 else 1.0
        xpc.sendDREF(dref, target)
        time.sleep(0.3)
        readback = xpc.getDREF(dref)
        assert abs(readback - target) < 0.01, \
            f"wrote {target} but read {readback}"
    finally:
        xpc.sendDREF(dref, original)
        time.sleep(0.2)


def test_sendCMND_pauses_simulator():
    xpc = new_client()
    try:
        xpc.sendCMND('sim/operation/pause_on')
        time.sleep(0.3)
        paused = xpc.getDREF('sim/time/paused')
        assert paused >= 0.5, f"expected sim to be paused, got sim/time/paused={paused}"
    finally:
        xpc.sendCMND('sim/operation/pause_off')
        time.sleep(0.3)


def test_pauseSIM_toggles_pause_state():
    xpc = new_client()
    try:
        xpc.pauseSIM(True)
        time.sleep(0.3)
        assert xpc.getDREF('sim/time/paused') >= 0.5, "pauseSIM(True) did not pause the sim"
        xpc.pauseSIM(False)
        time.sleep(0.3)
        assert xpc.getDREF('sim/time/paused') < 0.5, "pauseSIM(False) did not unpause the sim"
    finally:
        xpc.pauseSIM(False)


def test_getPOSI_returns_13_tuple_with_valid_ranges():
    xpc = new_client()
    posi = xpc.getPOSI()
    assert len(posi) == 13, f"expected 13 values, got {len(posi)}"
    lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r = posi
    assert -90.0 <= lat <= 90.0, f"latitude out of range: {lat}"
    assert -180.0 <= lon <= 180.0, f"longitude out of range: {lon}"
    assert -500.0 <= ele <= 40000.0, f"elevation looks wrong: {ele}"
    # X-Plane's RPOS heading can be signed depending on convention; just bound its magnitude
    assert -360.0 <= psi_true <= 360.0, f"heading looks wrong: {psi_true}"


def test_sendPOSI_small_shift_roundtrip():
    xpc = new_client()
    xpc.pauseSIM(True)
    try:
        time.sleep(0.3)
        lat, lon, ele, y_agl, phi, theta, psi, *_ = xpc.getPOSI()
        # ~11m east shift — small enough to avoid scenery reloads
        new_lat = lat + 1e-4
        xpc.sendPOSI(lat=new_lat, lon=lon, elev=ele, phi=phi, theta=theta, psi_true=psi)
        time.sleep(0.8)
        lat2, lon2, ele2, *_ = xpc.getPOSI()
        assert abs(lat2 - new_lat) < 1e-3, \
            f"latitude was not applied: target={new_lat}, got={lat2}"
        assert abs(lon2 - lon) < 1e-3, \
            f"longitude drifted: before={lon}, after={lon2}"
        # restore
        xpc.sendPOSI(lat=lat, lon=lon, elev=ele, phi=phi, theta=theta, psi_true=psi)
        time.sleep(0.5)
    finally:
        xpc.pauseSIM(False)


def test_sendCTRL_applies_park_brake_and_flaps():
    xpc = new_client()
    xpc.pauseSIM(True)
    try:
        time.sleep(0.3)
        orig_park = xpc.getDREF("sim/cockpit2/controls/parking_brake_ratio")
        orig_flaps = xpc.getDREF("sim/cockpit2/controls/flap_ratio")
        xpc.sendCTRL(
            lat_control=0.0, lon_control=0.0, rudder_control=0.0,
            throttle=0.0, gear=1, flaps=0.5, speedbrakes=0.0, park_brake=1.0,
        )
        time.sleep(0.5)
        assert xpc.getDREF("sim/cockpit2/controls/parking_brake_ratio") >= 0.9, \
            "park brake was not set to 1.0"
        assert abs(xpc.getDREF("sim/cockpit2/controls/flap_ratio") - 0.5) < 0.1, \
            "flaps were not set to 0.5"
    finally:
        xpc.sendCTRL(
            lat_control=0.0, lon_control=0.0, rudder_control=0.0,
            throttle=0.0, gear=1, flaps=orig_flaps, speedbrakes=0.0, park_brake=orig_park,
        )
        time.sleep(0.3)
        xpc.pauseSIM(False)


# ---------- subscription tests ----------

def test_subscribeDREFs_populates_current_values():
    xpc = new_client()
    xpc.subscribeDREFs(
        [("sim/time/total_running_time_sec", 10),
         ("sim/flightmodel/position/latitude", 10)],
    )
    # subscribe now blocks until at least one value lands
    for name in ("sim/time/total_running_time_sec", "sim/flightmodel/position/latitude"):
        entry = xpc.current_dref_values[name]
        assert entry['value'] is not None, f"{name} has no value"
        assert entry['timestamp'] is not None, f"{name} has no timestamp"


def test_subscribeDREFs_history_buffer_respects_window():
    xpc = new_client()
    xpc.subscribeDREFs(
        [("sim/time/total_running_time_sec", 20)],
        history=1.0,
    )
    time.sleep(2.0)
    hist = xpc.current_dref_values["sim/time/total_running_time_sec"]['history']
    # window=1s at 20Hz should be ~20 entries; allow generous slack for jitter
    assert 10 <= len(hist) <= 40, \
        f"expected ~20 history entries, got {len(hist)}"


# NOTE: no live test for "unknown DataRef → TimeoutError" because X-Plane
# actually replies to RREF requests for nonexistent DataRefs with a sentinel
# value, so the blocking wait returns normally. The mock-based test
# `test_missing_dref_raises` in test_subscribe_blocking.py covers the
# timeout-and-retry path against a server that truly doesn't respond.


# ---------- recording tests ----------

def test_recording_collects_raw_samples():
    xpc = new_client()
    xpc.subscribeDREFs([("sim/time/total_running_time_sec", 10)])
    xpc.startRECORDING()
    time.sleep(2.0)
    data = xpc.stopRECORDING()
    assert isinstance(data, dict), f"expected dict, got {type(data).__name__}"
    samples = data["sim/time/total_running_time_sec"]
    assert 10 <= len(samples) <= 30, f"expected ~20 samples, got {len(samples)}"
    first = samples[0]
    assert 'value' in first and 'timestamp' in first, \
        f"sample missing keys: {first.keys()}"


def test_recording_synchronize_to_specific_hz():
    xpc = new_client()
    xpc.subscribeDREFs([
        ("sim/time/total_running_time_sec", 10),
        ("sim/flightmodel/position/latitude", 10),
    ])
    xpc.startRECORDING()
    time.sleep(3.0)
    df = xpc.stopRECORDING(synchronize=5)
    assert df is not None and len(df) > 0, "synchronized DataFrame is empty"
    assert "sim/time/total_running_time_sec" in df.columns
    assert "sim/flightmodel/position/latitude" in df.columns
    # expect ~15 rows at 5Hz for ~3s of recording; broad range for jitter
    assert 8 <= len(df) <= 25, f"unexpected row count: {len(df)}"


def test_recording_synchronize_true_uses_lowest_freq():
    xpc = new_client()
    xpc.subscribeDREFs([
        ("sim/time/total_running_time_sec", 10),
        ("sim/flightmodel/position/latitude", 5),
    ])
    xpc.startRECORDING()
    time.sleep(3.0)
    df = xpc.stopRECORDING(synchronize=True)
    assert df is not None and len(df) > 0, "synchronized DataFrame is empty"
    # 5 Hz over ~3s → ~15 rows; allow slack
    assert 8 <= len(df) <= 25, f"unexpected row count at lowest freq: {len(df)}"


def test_stopRECORDING_without_start_raises():
    xpc = new_client()
    xpc.subscribeDREFs([("sim/time/total_running_time_sec", 10)])
    try:
        xpc.stopRECORDING()
    except RuntimeError:
        return
    raise AssertionError("expected RuntimeError when stopping a recording that was not started")


TESTS = [
    test_getDREF_returns_sensible_value,
    test_sendDREF_then_getDREF_roundtrip,
    test_sendCMND_pauses_simulator,
    test_pauseSIM_toggles_pause_state,
    test_getPOSI_returns_13_tuple_with_valid_ranges,
    test_sendPOSI_small_shift_roundtrip,
    test_sendCTRL_applies_park_brake_and_flaps,
    test_subscribeDREFs_populates_current_values,
    test_subscribeDREFs_history_buffer_respects_window,
    test_recording_collects_raw_samples,
    test_recording_synchronize_to_specific_hz,
    test_recording_synchronize_true_uses_lowest_freq,
    test_stopRECORDING_without_start_raises,
]


def main() -> int:
    if not probe_xplane():
        print(f"SKIP all: X-Plane did not respond at {XPLANE_HOST}:{XPLANE_PORT} within 2s")
        return 0

    print(f"X-Plane reachable at {XPLANE_HOST}:{XPLANE_PORT}; running {len(TESTS)} tests.\n")
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
