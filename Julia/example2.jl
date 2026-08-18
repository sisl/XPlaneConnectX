using Printf

# import the XPlaneConnectX code
include("XPlaneConnectX.jl")

# helper function to print state
function print_state(state)
    println("-"^98)
    for k in keys(state)
        println(@sprintf("%-40s %-30s %s", k, state[k]["value"], state[k]["timestamp"]))
    end
end

subscribed_drefs = [
    ("sim/flightmodel/position/groundspeed",10),    # ground speed in m/s at 10Hz
    ("sim/flightmodel/position/mag_psi",10),       # magnetic heading in degrees at 10Hz
    ("sim/flightmodel/weight/m_fuel[0]",10),       # magnetic heading in degrees at 10Hz
]

# this assumes you are running X-Plane on the same machine as your code and use the default port 49000 that X-Plane uses for UDP
xpc = XPlaneConnectX(ip="192.168.0.11", port=49000) 

# subscribe to datarefs
subscribeDREFs(xpc,subscribed_drefs)    # the current values are stored in xpc.current_dref_values



# Taxi for 10s and print the observed DataRefs once per second
for i=1:10
    print_state(xpc.current_dref_values)
    sleep(1)
end

