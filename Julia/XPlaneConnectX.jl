using Sockets
using Base.Threads
using Dates

mutable struct XPlaneConnectX
    sock::UDPSocket
    ip::String
    port::Int
    subscribed_drefs::Vector{Tuple{String, Int}}
    reverse_index::Dict{Int, String}
    current_dref_values::Dict{String, Dict{String, Any}}
end

"""
    XPlaneConnectX(; ip::String="127.0.0.1", port::Int64=49000)

Initialize an `XPlaneConnectX` instance.

# Arguments
- `ip::String="127.0.0.1"`: IP address where X-Plane can be found. Defaults to '127.0.0.1'.
- `port::Int=49000`: Port to communicate with X-Plane. This can be found and changed in the X-Plane network settings. Defaults to 49000.

# Returns
An instance of `XPlaneConnectX` initialized with a UDP socket, the provided IP address, and port.

# Examples
```julia
xpc = XPlaneConnectX() # Uses default IP and port
xpc = XPlaneConnectX(ip="192.168.1.10", port=50000) # Custom IP and port
```
"""
function XPlaneConnectX(; ip::String="127.0.0.1", port::Int64=49000)
    sock = UDPSocket()
    xpc = XPlaneConnectX(sock, ip, port, [], Dict(), Dict())
    return xpc
end

"""
    subscribeDREFs(xpc::XPlaneConnectX, subscribed_drefs::Vector{Tuple{String, Int64}})

Permanently subscribe to a list of DataRefs with a certain frequency. This method is preferred for obtaining the most up-to-date values for DataRefs that will be used frequently during the runtime of your code. Examples include position, velocity, or attitude. The data will be asynchronously received and processed, unlike the synchronous `getDREF` or `getPOSI` methods. The most recent value for each subscribed DataRef is stored in `xpc.current_dref_values`, which is a dictionary with DataRefs as keys. Each entry contains another dictionary with the keys `"value"` and `"timestamp"` representing the most recent value and the time it was received, respectively.

# Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` to which the DataRefs will be subscribed.
- `subscribed_drefs::Vector{Tuple{String, Int64}}`: List of (DataRef, frequency) tuples to be permanently observed.

# Example
```julia
xpc = XPlaneConnectX()
subscribeDREFs(xpc, [("sim/cockpit2/controls/brake_fan_on", 2), ("sim/flightmodel/position/y_agl", 10)])
```
"""
function subscribeDREFs(xpc::XPlaneConnectX, subscribed_drefs::Vector{Tuple{String, Int64}})
    xpc.subscribed_drefs = subscribed_drefs
    xpc.reverse_index = Dict(i => sdf[1] for (i, sdf) in enumerate(subscribed_drefs))
    xpc.current_dref_values = Dict(sdf[1] => Dict("value" => nothing, "timestamp" => nothing) for sdf in subscribed_drefs)
    _create_observation_requests(xpc)
    _observe_async(xpc)
end

function _create_observation_requests(xpc::XPlaneConnectX)
    for (i, sdf) in enumerate(xpc.subscribed_drefs)
        dref = sdf[1]
        prefix = "RREF"  # "Request DREF"
        freq = Int32(sdf[2])
        buffer = IOBuffer()
        write(buffer, prefix)                     # 4s
        write(buffer, UInt8(0))                   # x (padding byte)
        write(buffer, freq)                       # i
        write(buffer, Int32(i))                   # i
        write(buffer, dref)                       # 400s
        write(buffer, repeat([UInt8(0)], 400 - length(dref)))  # pad the string to 400 bytes
        send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))
    end
end


function _observe(xpc::XPlaneConnectX,delay::Float64)
    sleep(delay)    # without this, recvfrom blocks
    while true
        addr, data = recvfrom(xpc.sock)
        header = String(data[1:4])
        if header == "RREF"
            if ((length(data) - 5) % 8) != 0
                error("Received data is not 8 bytes long")
            end
            no_packets = div(length(data) - 5, 8)
            for p_idx=1:no_packets
                p_data = data[(5 + (p_idx-1) * 8 + 1):(5 + (p_idx) * 8)]
                idx, value = reinterpret(Int32, p_data[1:4])[1], reinterpret(Float32, p_data[5:8])[1]
                if idx in keys(xpc.reverse_index)
                    # write current values to the xpc.current_dref_values dictionary
                    xpc.current_dref_values[xpc.reverse_index[idx]] = Dict("value" => value, "timestamp" => now())
                else
                    error("Received a packet with invalid index.")
                end
            end
        end
    end
end

function _observe_async(xpc::XPlaneConnectX;delay::Float64=0.01)
    @async _observe(xpc,delay)

    #block the synchronous code as well to avoid that xpc.current_dref_values is read before they are ready
    sleep(delay)    
    # _observe(xpc)
end

"""
    getDREF(xpc::XPlaneConnectX, dref::String) -> Float32

Gets the current value of a DataRef. This function is intended for one-time use. For DataRefs with frequent use, consider using the permanently observed DataRefs set up when initializing the `XPlaneConnectX` object.

# Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` to perform the query.
- `dref::String`: DataRef to be queried.

# Returns
- `Float32`: The value of the DataRef `dref`.

# Example
```julia
xpc = XPlaneConnectX()
value = getDREF(xpc, "sim/cockpit2/controls/brake_fan_on")
```
"""
function getDREF(xpc::XPlaneConnectX, dref::String)
    # send request
    temp_socket = UDPSocket()
    idx = length(keys(xpc.reverse_index)) + 10
    prefix = "RREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Int32(100))         
    write(buffer, Int32(idx))                  
    write(buffer, dref)                       
    write(buffer, repeat([UInt8(0)], 400 - length(dref)))  # pad the string to 400 bytes
    send(temp_socket, IPv4(xpc.ip), xpc.port, take!(buffer))    # send with temp_socket to avoid conflicts

    # wait for response
    addr, data = recvfrom(temp_socket)
    header = String(data[1:4])
    if header == "RREF"
        if ((length(data) - 5) % 8) != 0
            error("Received data is not 8 bytes long")
        end
        p_data = data[6:end]
        idx_received, value = reinterpret(Int32, p_data[1:4])[1], reinterpret(Float32, p_data[5:end])[1] 
        if idx_received != idx
            error("Received a packet with invalid index.")
        end
    end

    # unsubscribe from DataRef
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Int32(0)) # set freqency to 0 to unsubscribe         
    write(buffer, Int32(idx))                  
    write(buffer, dref)                       
    write(buffer, repeat([UInt8(0)], 400 - length(dref)))  # pad the string to 400 bytes
    send(temp_socket, IPv4(xpc.ip), xpc.port, take!(buffer)) 
    
    return value
end

"""
    sendDREF(xpc::XPlaneConnectX, dref::String, value::Any)

Writes a value to the specified DataRef, provided that the DataRef is writable.

# Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` used to send the data.
- `dref::String`: The DataRef to be changed.
- `value::Any`: The value to which the DataRef should be set.

# Example
```julia
xpc = XPlaneConnectX()
sendDREF(xpc, "sim/cockpit/electrical/landing_lights_on", 1.0)  # Turn on the landing lights
```
"""
function sendDREF(xpc::XPlaneConnectX, dref::String, value::Any)
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)                     # 4s
    write(buffer, UInt8(0))                   # x (padding byte)
    write(buffer, Float32(value))             # f
    write(buffer, dref)                       # 500s
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))
end

"""
    sendCMND(xpc::XPlaneConnectX, command::String)

Sends simulator commands to the simulator. These commands are not for (only) controlling airplanes but for operating the simulator itself (e.g., closing X-Plane or taking a screenshot).

# Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` used to send the command.
- `command::String`: The command to be executed by the simulator.

# Example
```julia
xpc = XPlaneConnectX()
sendCMND(xpc, "sim/operation/quit")  # Example command to close X-Plane
```
"""
function sendCMND(xpc::XPlaneConnectX, command::String)
    prefix = "CMND"
    buffer = IOBuffer()
    write(buffer, prefix)                    # 4s
    write(buffer, UInt8(0))                  # x (padding byte)
    write(buffer, command)                   # 500s
    write(buffer, repeat([UInt8(0)], 500 - length(command)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))
end

"""
    sendPOSI(xpc::XPlaneConnectX; lat::Any, lon::Any, elev::Any, phi::Any, theta::Any, psi_true::Any, ac::Int=0)

Sets the global position and attitude of an airplane. This is the only method to set the latitude and longitude of an airplane, as these DataRefs are not writable.

# Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` used to send the position data.
- `lat::Any`: Latitude in degrees. For precise placement, this should be a `Float64`.
- `lon::Any`: Longitude in degrees. For precise placement, this should be a `Float64`.
- `elev::Any`: Altitude above mean sea level in meters. This should be a `Float64`.
- `phi::Any`: Roll angle in degrees. This should be a `Float32`.
- `theta::Any`: Pitch angle in degrees. This should be a `Float32`.
- `psi_true::Any`: True heading (not magnetic) in degrees. This should be a `Float32`.
- `ac::Int=0`: Index of the aircraft to set the position for. `0` refers to the ego aircraft. Defaults to `0`.

# Notes
- Ensure that the latitude and longitude values are provided as `Float64` for double precision, while roll, pitch, and heading values should be provided as `Float32`.

# Example
```julia
xpc = XPlaneConnectX()
sendPOSI(xpc, 37.7749, -122.4194, 100.0, 0.0, 0.0, 90.0)
```
"""
function sendPOSI(xpc::XPlaneConnectX; lat::Any, lon::Any, elev::Any, phi::Any, theta::Any, psi_true::Any, ac::Int=0)
    prefix = "VEHS"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Int32(ac))
    write(buffer, Float64(lat))
    write(buffer, Float64(lon))
    write(buffer, Float64(elev))
    write(buffer, Float32(psi_true))
    write(buffer, Float32(theta))
    write(buffer, Float32(phi))
    msg = take!(buffer)
    send(xpc.sock, IPv4(xpc.ip), xpc.port, msg)
    send(xpc.sock, IPv4(xpc.ip), xpc.port, msg)   # send twice since the elevation is erroneously calculated based on initial location
end

"""
    getPOSI(xpc::XPlaneConnectX) -> Tuple{Float64, Float64, Float64, Float32, Float32, Float32, Float32, Float32, Float32, Float32, Float32, Float32}

Gets the global position of the ego aircraft. If this information is needed frequently, consider using the permanently observed DataRefs set up when initializing the `XPlaneConnectX` object.

The function retrieves the following values, which correspond to DataRefs:

- `sim/flightmodel/position/longitude`
- `sim/flightmodel/position/latitude`
- `sim/flightmodel/position/elevation`
- `sim/flightmodel/position/y_agl`
- `sim/flightmodel/position/true_theta`
- `sim/flightmodel/position/true_psi`
- `sim/flightmodel/position/true_phi`
- `sim/flightmodel/position/local_vx`
- `sim/flightmodel/position/local_vy`
- `sim/flightmodel/position/local_vz`
- `sim/flightmodel/position/Prad`
- `sim/flightmodel/position/Qrad`
- `sim/flightmodel/position/Rrad`

# Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX`.

# Returns
- A tuple containing:
  - `Float64`: Latitude in degrees
  - `Float64`: Longitude in degrees
  - `Float64`: Elevation above mean sea level in meters
  - `Float32`: Elevation above the terrain in meters
  - `Float32`: Roll angle in degrees
  - `Float32`: Pitch angle in degrees
  - `Float32`: True heading (not magnetic) in degrees
  - `Float32`: Speed in east direction in meters per second
  - `Float32`: Speed in up direction in meters per second
  - `Float32`: Speed in south direction in meters per second
  - `Float32`: Roll rate in radians per second
  - `Float32`: Pitch rate in radians per second
  - `Float32`: Yaw rate in radians per second

# Example
```julia
xpc = XPlaneConnectX()
lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r = getPOSI(xpc)
```
"""
function getPOSI(xpc::XPlaneConnectX)
    # send request
    temp_socket = UDPSocket()
    prefix = "RPOS"
    freq = "100"    # request at 100Hz
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, freq)    
    write(buffer, repeat([UInt8(0)], 10 - length(freq)))    # padding
    send(temp_socket, IPv4(xpc.ip), xpc.port, take!(buffer)) 

    # wait for response
    addr, data = recvfrom(temp_socket)
    header = String(data[1:4])
    if header == "RPOS"
        lon = reinterpret(Float64, data[6:13])[1]           # longitude in degrees
        lat = reinterpret(Float64, data[14:21])[1]          # latitude in degrees
        ele = reinterpret(Float64, data[22:29])[1]          # elevation above mean sea level in meters
        y_agl = reinterpret(Float32, data[30:33])[1]        # elevation above the terrain in meters
        theta = reinterpret(Float32, data[34:37])[1]        # pitch angle in degrees
        psi_true = reinterpret(Float32, data[38:41])[1]     # true hheading in degrees
        phi = reinterpret(Float32, data[42:45])[1]          # roll angle in degrees
        vx = reinterpret(Float32, data[46:49])[1]           # speed in east direction in meters per second (OpenGL coordinate system x-axis, intertial)
        vy = reinterpret(Float32, data[50:53])[1]           # speed in up direction in meters per second (OpenGL coordinate system y-axis, intertial)
        vz = reinterpret(Float32, data[54:57])[1]           # speed in south direction in meters per second (OpenGL coordinate system z-axis, intertial)
        p = reinterpret(Float32, data[58:61])[1]            # roll rate in radians per second
        q = reinterpret(Float32, data[62:65])[1]            # pitch rate in radians per second
        r = reinterpret(Float32, data[66:69])[1]            # yaw rate in radians per second
    else
        error("Received invalid header.")
    end
    
    # unsubscribe
    freq = "0"    # unsubscribe by setting frequency to 0
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, freq)    
    write(buffer, repeat([UInt8(0)], 10 - length(freq)))    # padding
    send(temp_socket, IPv4(xpc.ip), xpc.port, take!(buffer)) 

    return lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r
end

"""
    sendCTRL(xpc::XPlaneConnectX; lat_control::Number, lon_control::Number, rudder_control::Number, throttle::Number, gear::Signed, flaps::Number, speedbrakes::Number, park_brake::Number)

Sends basic control inputs to the ego aircraft. For more fine-grained control, refer to the DataRefs that can be set using the `setDREF` method.

# Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX`.
- `lat_control::Number`: Lateral pilot input, representing yoke rotation or side stick left/right position. Ranges from `[-1, 1]`.
- `lon_control::Number`: Longitudinal pilot input, representing yoke or side stick forward/backward position. Ranges from `[-1, 1]`.
- `rudder_control::Number`: Rudder pilot input. Ranges from `[-1, 1]`.
- `throttle::Number`: Throttle position. Ranges from `[-1, 1]`, where `-1` indicates full reverse thrust and `1` indicates full forward thrust.
- `gear::Signed`: Requested gear position. `0` corresponds to gear up, and `1` corresponds to gear down.
- `flaps::Number`: Requested flaps position. Ranges from `[0, 1]`.
- `speedbrakes::Number`: Requested speedbrakes position. Possible values are `-0.5` (armed), `0` (retracted), and `1` (fully deployed).
- `park_brake::Number`: Requested park brake ratio. Ranges from `[0, 1]`.

# Example
```julia
xpc = XPlaneConnectX()
sendCTRL(xpc, lat_control=-0.2, lon_control=0.0, rudder_control=0.2, throttle=0.8, gear=1, flaps=0.5, speedbrakes=0, park_brake=0)
```
"""
function sendCTRL(xpc::XPlaneConnectX; lat_control::Number, lon_control::Number, rudder_control::Number, throttle::Number, gear::Signed, flaps::Number, speedbrakes::Number, park_brake::Number)
    # lateral control
    dref = "sim/cockpit2/controls/yoke_roll_ratio"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(lat_control))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer)) 

    # longitudinal control
    dref = "sim/cockpit2/controls/yoke_pitch_ratio"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(lon_control))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer)) 

    # rudder control
    dref = "sim/cockpit2/controls/yoke_heading_ratio"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(rudder_control))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))

    # throttle
    dref = "sim/cockpit2/engine/actuators/throttle_jet_rev_ratio_all"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(throttle))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))

    # gear
    dref = "sim/cockpit/switches/gear_handle_status"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(gear))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))

    # flaps
    # dref = "sim/cockpit2/controls/flap_handle_request_ratio" #this only for X-Plane 12.0+
    dref = "sim/cockpit2/controls/flap_ratio"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(flaps))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))

    # speedbrakes
    dref = "sim/cockpit2/controls/speedbrake_ratio"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(speedbrakes))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))

    # park brake
    dref = "sim/cockpit2/controls/parking_brake_ratio"
    prefix = "DREF"
    buffer = IOBuffer()
    write(buffer, prefix)
    write(buffer, UInt8(0))
    write(buffer, Float32(park_brake))
    write(buffer, dref)
    write(buffer, repeat([UInt8(0)], 500 - length(dref)))  # pad the string to 500 bytes
    send(xpc.sock, IPv4(xpc.ip), xpc.port, take!(buffer))   
end

"""
    pauseSIM(xpc::XPlaneConnectX, set_pause::Bool)

Pauses or unpauses the simulator based on the given input.

# Arguments
- `xpc::XPlaneConnectX`: The `XPlaneConnectX` object used to interact with the simulator.
- `set_pause::Bool`: If `true`, the simulator is paused. If `false`, the simulator is unpaused.

# Example
```julia
xpc = XPlaneConnectX()
pauseSIM(xpc, true)  # Pauses the simulator
pauseSIM(xpc, false) # Unpauses the simulator
```
"""
function pauseSIM(xpc::XPlaneConnectX, set_pause::Bool)
    if set_pause
        sendCMND(xpc, "sim/operation/pause_on")
    else
        sendCMND(xpc, "sim/operation/pause_off")
    end
end
