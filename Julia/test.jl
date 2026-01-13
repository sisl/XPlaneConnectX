using Printf


# import the XPlaneConnectX code
include("XPlaneConnectX.jl")


subscribed_drefs = [
    ("sim/flightmodel/position/groundspeed",10),    # ground speed in m/s at 10Hz
    ("sim/flightmodel/position/mag_psi",10),       # magnetic heading in degrees at 10Hz
]

# this assumes you are running X-Plane on the same machine as your code and use the default port 49000 that X-Plane uses for UDP
xpc = XPlaneConnectX(ip="127.0.0.1", port=49000) 

# subscribe to datarefs
subscribeDREFs(xpc,subscribed_drefs)

startRECORDING(xpc)

sleep(5)

recording = stopRECORDING(xpc)

println(recording)