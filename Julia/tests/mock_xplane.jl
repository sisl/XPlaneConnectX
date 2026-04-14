# Mock UDP X-Plane server used by the XPlaneConnectX tests.
#
# Listens for RREF subscription requests and — depending on its configuration —
# either acknowledges them with a synthetic value, drops the first few requests
# for a given DataRef (simulating packet loss), or never responds at all.

using Sockets

mutable struct MockXPlane
    sock::UDPSocket
    port::Int
    drop_first_k::Dict{String, Int}
    never_respond::Set{String}
    response_value::Float32
    requests::Vector{Tuple{String, Int, Int}}  # (dref, idx, freq)
    lock::ReentrantLock
    running::Bool
end

function _bind_free_udp!(sock::UDPSocket; tries::Int=30)
    for _ in 1:tries
        port = rand(49152:64999)
        try
            bind(sock, ip"127.0.0.1", port) && return port
        catch
            # port in use; try another
        end
    end
    error("could not bind to a free UDP port after $tries tries")
end

function MockXPlane(; drop_first_k::Dict{String, Int}=Dict{String, Int}(),
                      never_respond::Set{String}=Set{String}(),
                      response_value::Real=1.23)
    sock = UDPSocket()
    port = _bind_free_udp!(sock)
    mock = MockXPlane(sock, port, copy(drop_first_k), copy(never_respond),
                      Float32(response_value), Tuple{String, Int, Int}[],
                      ReentrantLock(), true)
    @async _mock_loop(mock)
    sleep(0.05)  # yield so the async loop reaches recvfrom before the caller sends
    return mock
end

function _mock_loop(mock::MockXPlane)
    while mock.running
        local addr, data
        try
            addr, data = recvfrom(mock.sock)
        catch
            break  # socket closed
        end
        if length(data) != 413 || String(data[1:4]) != "RREF"
            continue
        end
        freq = reinterpret(Int32, data[6:9])[1]
        idx = reinterpret(Int32, data[10:13])[1]
        dref_raw = data[14:413]
        null_pos = findfirst(iszero, dref_raw)
        dref_bytes = null_pos === nothing ? dref_raw : dref_raw[1:null_pos-1]
        dref = String(dref_bytes)

        should_respond = lock(mock.lock) do
            push!(mock.requests, (dref, Int(idx), Int(freq)))
            if dref in mock.never_respond
                return false
            end
            remaining = get(mock.drop_first_k, dref, 0)
            if remaining > 0
                mock.drop_first_k[dref] = remaining - 1
                return false
            end
            return true
        end

        if should_respond
            buf = IOBuffer()
            write(buf, "RREF")
            write(buf, UInt8(0))
            write(buf, Int32(idx))
            write(buf, Float32(mock.response_value))
            try
                send(mock.sock, addr.host, addr.port, take!(buf))
            catch
                break
            end
        end
    end
end

function received_for(mock::MockXPlane, dref::String)
    lock(mock.lock) do
        count(x -> x[1] == dref, mock.requests)
    end
end

function all_requests(mock::MockXPlane)
    lock(mock.lock) do
        copy(mock.requests)
    end
end

function Base.close(mock::MockXPlane)
    mock.running = false
    try
        close(mock.sock)
    catch
    end
end
