# End-to-end tests for XPlaneConnectX against a running X-Plane instance.
#
# Run with:
#     julia --project=Julia Julia/tests/test_live_xplane.jl
#
# Environment variables:
#     XPLANE_HOST (default 127.0.0.1)
#     XPLANE_PORT (default 49000)
#
# The test suite first probes X-Plane; if it doesn't respond within ~2 seconds
# all tests are skipped with a non-failing exit code so this file is safe to
# run in environments without a simulator.
#
# What the tests will do (all reversible): briefly toggle landing lights,
# pause and unpause the simulator, shift the aircraft position by a fraction
# of a degree and then restore it, apply zero-ish control inputs and restore
# them, and subscribe/record a handful of read-only DataRefs. No flight reset
# is issued and no destructive commands are sent.

using Sockets

const HERE = @__DIR__
const PARENT = dirname(HERE)

include(joinpath(PARENT, "XPlaneConnectX.jl"))

const XPLANE_HOST = get(ENV, "XPLANE_HOST", "127.0.0.1")
const XPLANE_PORT = parse(Int, get(ENV, "XPLANE_PORT", "49000"))


function probe_xplane(timeout::Float64=2.0)::Bool
    sock = UDPSocket()
    dref = "sim/time/total_running_time_sec"
    idx = 12345
    buf = IOBuffer()
    write(buf, "RREF"); write(buf, UInt8(0))
    write(buf, Int32(1)); write(buf, Int32(idx))
    write(buf, dref); write(buf, repeat([UInt8(0)], 400 - length(dref)))
    try
        send(sock, IPv4(XPLANE_HOST), XPLANE_PORT, take!(buf))
    catch
        close(sock)
        return false
    end

    result = Ref(false)
    done = Ref(false)
    @async try
        _, data = recvfrom(sock)
        result[] = length(data) >= 4 && String(data[1:4]) == "RREF"
        done[] = true
    catch
        done[] = true
    end
    timedwait(() -> done[], timeout; pollint=0.05)

    try
        unsub = IOBuffer()
        write(unsub, "RREF"); write(unsub, UInt8(0))
        write(unsub, Int32(0)); write(unsub, Int32(idx))
        write(unsub, dref); write(unsub, repeat([UInt8(0)], 400 - length(dref)))
        send(sock, IPv4(XPLANE_HOST), XPLANE_PORT, take!(unsub))
    catch
    end
    try; close(sock); catch; end
    return result[]
end


new_client() = XPlaneConnectX(ip=XPLANE_HOST, port=XPLANE_PORT)


# ---------- synchronous method tests ----------

function test_getDREF_returns_sensible_value()
    xpc = new_client()
    v = getDREF(xpc, "sim/time/total_running_time_sec")
    v isa AbstractFloat || error("expected a float, got $(typeof(v))")
    v > 0 || error("total_running_time_sec should be > 0, got $v")
end

function test_sendDREF_then_getDREF_roundtrip()
    xpc = new_client()
    dref = "sim/cockpit/electrical/landing_lights_on"
    original = getDREF(xpc, dref)
    try
        target = original >= 0.5 ? 0.0 : 1.0
        sendDREF(xpc, dref, target)
        sleep(0.3)
        readback = getDREF(xpc, dref)
        abs(readback - target) < 0.01 ||
            error("wrote $target but read $readback")
    finally
        sendDREF(xpc, dref, original)
        sleep(0.2)
    end
end

function test_sendCMND_pauses_simulator()
    xpc = new_client()
    try
        sendCMND(xpc, "sim/operation/pause_on")
        sleep(0.3)
        paused = getDREF(xpc, "sim/time/paused")
        paused >= 0.5 || error("expected sim to be paused, got sim/time/paused=$paused")
    finally
        sendCMND(xpc, "sim/operation/pause_off")
        sleep(0.3)
    end
end

function test_pauseSIM_toggles_pause_state()
    xpc = new_client()
    try
        pauseSIM(xpc, true)
        sleep(0.3)
        getDREF(xpc, "sim/time/paused") >= 0.5 ||
            error("pauseSIM(true) did not pause the sim")
        pauseSIM(xpc, false)
        sleep(0.3)
        getDREF(xpc, "sim/time/paused") < 0.5 ||
            error("pauseSIM(false) did not unpause the sim")
    finally
        pauseSIM(xpc, false)
    end
end

function test_getPOSI_returns_13_tuple_with_valid_ranges()
    xpc = new_client()
    posi = getPOSI(xpc)
    length(posi) == 13 || error("expected 13 values, got $(length(posi))")
    lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r = posi
    (-90.0 <= lat <= 90.0) || error("latitude out of range: $lat")
    (-180.0 <= lon <= 180.0) || error("longitude out of range: $lon")
    (-500.0 <= ele <= 40000.0) || error("elevation looks wrong: $ele")
    # X-Plane's RPOS heading can be signed depending on convention; bound its magnitude
    (-360.0 <= psi_true <= 360.0) || error("heading looks wrong: $psi_true")
end

function test_sendPOSI_small_shift_roundtrip()
    xpc = new_client()
    pauseSIM(xpc, true)
    try
        sleep(0.3)
        lat, lon, ele, y_agl, phi, theta, psi = getPOSI(xpc)[1:7]
        new_lat = lat + 1e-4  # ~11m offset — too small to reload scenery
        sendPOSI(xpc, lat=new_lat, lon=lon, elev=ele, phi=phi, theta=theta, psi_true=psi)
        sleep(0.8)
        lat2, lon2 = getPOSI(xpc)[1:2]
        abs(lat2 - new_lat) < 1e-3 ||
            error("latitude was not applied: target=$new_lat, got=$lat2")
        abs(lon2 - lon) < 1e-3 ||
            error("longitude drifted: before=$lon, after=$lon2")
        sendPOSI(xpc, lat=lat, lon=lon, elev=ele, phi=phi, theta=theta, psi_true=psi)
        sleep(0.5)
    finally
        pauseSIM(xpc, false)
    end
end

function test_sendCTRL_applies_park_brake_and_flaps()
    xpc = new_client()
    pauseSIM(xpc, true)
    orig_park = 0.0
    orig_flaps = 0.0
    try
        sleep(0.3)
        orig_park = getDREF(xpc, "sim/cockpit2/controls/parking_brake_ratio")
        orig_flaps = getDREF(xpc, "sim/cockpit2/controls/flap_ratio")
        sendCTRL(xpc,
            lat_control=0.0, lon_control=0.0, rudder_control=0.0,
            throttle=0.0, gear=1, flaps=0.5, speedbrakes=0.0, park_brake=1.0,
        )
        sleep(0.5)
        pb = getDREF(xpc, "sim/cockpit2/controls/parking_brake_ratio")
        pb >= 0.9 || error("park brake was not set to 1.0, got $pb")
        fl = getDREF(xpc, "sim/cockpit2/controls/flap_ratio")
        abs(fl - 0.5) < 0.1 || error("flaps were not set to 0.5, got $fl")
    finally
        sendCTRL(xpc,
            lat_control=0.0, lon_control=0.0, rudder_control=0.0,
            throttle=0.0, gear=1, flaps=orig_flaps, speedbrakes=0.0, park_brake=orig_park,
        )
        sleep(0.3)
        pauseSIM(xpc, false)
    end
end

# ---------- subscription tests ----------

function test_subscribeDREFs_populates_current_values()
    xpc = new_client()
    subscribeDREFs(xpc,
        [("sim/time/total_running_time_sec", 10),
         ("sim/flightmodel/position/latitude", 10)],
    )
    # subscribe now blocks until at least one value lands
    for name in ("sim/time/total_running_time_sec", "sim/flightmodel/position/latitude")
        entry = xpc.current_dref_values[name]
        entry["value"] !== nothing || error("$name has no value")
        entry["timestamp"] !== nothing || error("$name has no timestamp")
    end
end

# ---------- recording tests ----------

function test_recording_collects_raw_samples()
    xpc = new_client()
    subscribeDREFs(xpc, [("sim/time/total_running_time_sec", 10)])
    startRECORDING(xpc)
    sleep(2.0)
    data = stopRECORDING(xpc)
    data isa Dict || error("expected Dict, got $(typeof(data))")
    samples = data["sim/time/total_running_time_sec"]
    (10 <= length(samples) <= 30) ||
        error("expected ~20 samples, got $(length(samples))")
    first = samples[1]
    haskey(first, "value") && haskey(first, "timestamp") ||
        error("sample missing keys: $(keys(first))")
end

function test_recording_synchronize_to_specific_hz()
    xpc = new_client()
    subscribeDREFs(xpc, [
        ("sim/time/total_running_time_sec", 10),
        ("sim/flightmodel/position/latitude", 10),
    ])
    startRECORDING(xpc)
    sleep(3.0)
    df = stopRECORDING(xpc, synchronize=5)
    (df !== nothing && nrow(df) > 0) || error("synchronized DataFrame is empty")
    cols = names(df)
    "sim/time/total_running_time_sec" in cols ||
        error("missing total_running_time_sec column: $cols")
    "sim/flightmodel/position/latitude" in cols ||
        error("missing latitude column: $cols")
    (8 <= nrow(df) <= 25) || error("unexpected row count: $(nrow(df))")
end

function test_recording_synchronize_true_uses_lowest_freq()
    xpc = new_client()
    subscribeDREFs(xpc, [
        ("sim/time/total_running_time_sec", 10),
        ("sim/flightmodel/position/latitude", 5),
    ])
    startRECORDING(xpc)
    sleep(3.0)
    df = stopRECORDING(xpc, synchronize=true)
    (df !== nothing && nrow(df) > 0) || error("synchronized DataFrame is empty")
    # 5 Hz over ~3s → ~15 rows; allow slack
    (8 <= nrow(df) <= 25) || error("unexpected row count at lowest freq: $(nrow(df))")
end

function test_stopRECORDING_without_start_raises()
    xpc = new_client()
    subscribeDREFs(xpc, [("sim/time/total_running_time_sec", 10)])
    try
        stopRECORDING(xpc)
    catch
        return
    end
    error("expected stopRECORDING to throw when recording was not started")
end


const TESTS = [
    test_getDREF_returns_sensible_value,
    test_sendDREF_then_getDREF_roundtrip,
    test_sendCMND_pauses_simulator,
    test_pauseSIM_toggles_pause_state,
    test_getPOSI_returns_13_tuple_with_valid_ranges,
    test_sendPOSI_small_shift_roundtrip,
    test_sendCTRL_applies_park_brake_and_flaps,
    test_subscribeDREFs_populates_current_values,
    test_recording_collects_raw_samples,
    test_recording_synchronize_to_specific_hz,
    test_recording_synchronize_true_uses_lowest_freq,
    test_stopRECORDING_without_start_raises,
]

function main()
    if !probe_xplane()
        println("SKIP all: X-Plane did not respond at $XPLANE_HOST:$XPLANE_PORT within 2s")
        return
    end

    println("X-Plane reachable at $XPLANE_HOST:$XPLANE_PORT; running $(length(TESTS)) tests.\n")
    failures = 0
    for t in TESTS
        name = string(t)
        try
            t()
            println("OK   $name")
        catch e
            failures += 1
            println("FAIL $name")
            showerror(stdout, e)
            println()
        end
    end
    if failures > 0
        println("\n$failures/$(length(TESTS)) tests failed")
        exit(1)
    end
    println("\nAll $(length(TESTS)) tests passed")
end

main()
