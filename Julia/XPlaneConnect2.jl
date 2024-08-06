using Sockets
using Base.Threads
using Dates

struct XPlaneConnect2
    sock::UDPSocket
    ip::String
    port::Int
    observed_drefs::Vector{Tuple{String, Int}}
    reverse_index::Dict{Int, String}
    current_data::Dict{String, Dict{String, Any}}
end

function XPlaneConnect2(observed_drefs::Vector{Tuple{String, Int}}=[], ip::String="127.0.0.1", port::Int=49000)
    sock = UDPSocket()
    reverse_index = Dict(i => odf[1] for (i, odf) in enumerate(observed_drefs))
    current_data = Dict(odf[1] => Dict("value" => nothing, "timestamp" => nothing) for odf in observed_drefs)
    xpc = XPlaneConnect2(sock, ip, port, observed_drefs, reverse_index, current_data)
    _create_observation_requests(xpc)
    observe(xpc)
    return xpc
end

function _create_observation_requests(xpc::XPlaneConnect2)
    for (i, odf) in enumerate(xpc.observed_drefs)
        dref = odf[1]
        prefix = "RREF"  # "Request DREF"
        freq = Int32(odf[2])
        buffer = IOBuffer()
        write(buffer, prefix)                     # 4s
        write(buffer, UInt8(0))                   # x (padding byte)
        write(buffer, freq)                       # i
        write(buffer, Int32(i))                   # i
        write(buffer, dref)                       # 400s
        write(buffer, repeat([UInt8(0)], 400 - length(dref)))  # pad the string to 400 bytes
        send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))
        sleep(0.05)
    end
end

function _observe(xpc::XPlaneConnect2)
    while true
        addr, data = recvfrom(xpc.sock)
        header = String(data[1:4])
        if header != "RREF"
            error("Unknown packet")
        end
        if ((length(data) - 5) % 8) != 0
            error("Received data is not 8 bytes long")
        end
        no_packets = div(length(data) - 5, 8)
        for p_idx in 0:(no_packets - 1)
            p_data = data[(5 + p_idx * 8 + 1):(5 + (p_idx + 1) * 8)]
            idx, value = reinterpret(Int32, p_data[1:4])[1], reinterpret(Float32, p_data[5:8])[1]
            # write current values to the xpc.current_data dictionary
            xpc.current_data[xpc.reverse_index[idx]] = Dict("value" => value, "timestamp" => now())
        end
    end
end

function observe(xpc::XPlaneConnect2)
    @async _observe(xpc)
    # _observe(xpc)
end



function set_dref(xpc::XPlaneConnect2, dref::String, value::Any)
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)                     # 4s
    write(buffer, UInt8(0))                   # x (padding byte)
    write(buffer, Float32(value))             # f
    write(buffer, dref)                       # 500s
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))
end

function send_cmnd(xpc::XPlaneConnect2, command::String)
    prefix = "CMND"
    buffer = IOBuffer()
    write(buffer, prefix)                    # 4s
    write(buffer, UInt8(0))                  # x (padding byte)
    write(buffer, command)                       # 500s
    write(buffer, repeat([UInt8(0)], 500 - length(command)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))
end

function pause(xpc::XPlaneConnect2, set_pause::Bool)
    if set_pause
        send_cmnd(xpc, "sim/operation/pause_on")
    else
        send_cmnd(xpc, "sim/operation/pause_off")
    end
end
