# Tests for the blocking / retrying behavior of subscribeDREFs.
#
# Run directly with:
#     julia Julia/tests/test_subscribe_blocking.jl
#
# Uses only the standard library plus the packages already used by XPlaneConnectX.jl,
# and a lightweight mock UDP server.

const HERE = @__DIR__
const PARENT = dirname(HERE)

include(joinpath(PARENT, "XPlaneConnectX.jl"))
include(joinpath(HERE, "mock_xplane.jl"))

function test_retry_recovers()
    mock = MockXPlane(drop_first_k=Dict("dref/a" => 2, "dref/b" => 1))
    try
        xpc = XPlaneConnectX(ip="127.0.0.1", port=mock.port)
        subscribeDREFs(xpc,
            [("dref/a", 1), ("dref/b", 1), ("dref/c", 1)];
            timeout=5.0, retry_interval=0.3,
        )

        for name in ("dref/a", "dref/b", "dref/c")
            xpc.current_dref_values[name]["value"] !== nothing ||
                error("no value received for $name")
        end

        a_count = received_for(mock, "dref/a")
        b_count = received_for(mock, "dref/b")
        c_count = received_for(mock, "dref/c")
        a_count >= 3 || error("expected >=3 requests for dref/a, got $a_count")
        b_count >= 2 || error("expected >=2 requests for dref/b, got $b_count")
        c_count >= 1 || error("expected >=1 request for dref/c, got $c_count")
    finally
        close(mock)
    end
end

function test_missing_dref_raises()
    mock = MockXPlane(never_respond=Set(["dref/bad"]))
    try
        xpc = XPlaneConnectX(ip="127.0.0.1", port=mock.port)
        timeout = 1.0
        retry_interval = 0.3

        t0 = time()
        raised = nothing
        try
            subscribeDREFs(xpc,
                [("dref/ok", 1), ("dref/bad", 1)];
                timeout=timeout, retry_interval=retry_interval,
            )
        catch e
            raised = e
        end
        elapsed = time() - t0

        raised !== nothing || error("expected an error to be raised")
        msg = sprint(showerror, raised)
        occursin("dref/bad", msg) ||
            error("error should name dref/bad; got: $msg")
        occursin("dref/ok", msg) &&
            error("error should not name dref/ok; got: $msg")

        (timeout <= elapsed <= timeout + retry_interval + 0.5) ||
            error("elapsed $(elapsed)s outside expected range")

        xpc.current_dref_values["dref/ok"]["value"] !== nothing ||
            error("dref/ok should have received a value before the timeout")
    finally
        close(mock)
    end
end

function test_fast_return_happy_path()
    mock = MockXPlane()
    try
        xpc = XPlaneConnectX(ip="127.0.0.1", port=mock.port)
        drefs = [("dref/x", 1), ("dref/y", 1), ("dref/z", 1)]

        t0 = time()
        subscribeDREFs(xpc, drefs; timeout=5.0, retry_interval=0.5)
        elapsed = time() - t0

        elapsed < 0.3 ||
            error("happy-path subscribe took $(elapsed)s, expected <0.3s")
        for (name, _) in drefs
            xpc.current_dref_values[name]["value"] !== nothing ||
                error("no value for $name")
            c = received_for(mock, name)
            c == 1 || error("expected exactly 1 request for $name, got $c")
        end
    finally
        close(mock)
    end
end

const TESTS = [
    test_retry_recovers,
    test_missing_dref_raises,
    test_fast_return_happy_path,
]

function main()
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
