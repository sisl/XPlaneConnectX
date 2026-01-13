from Python3.XPlaneConnectX import XPlaneConnectX
import time

subscribed_drefs=[("sim/flightmodel/position/groundspeed",10),   # ground speed in m/s at 10Hz
                  ("sim/flightmodel/position/mag_psi",2),       # magnetic heading in degrees at 10Hz
                 ]   

# this assumes you are running X-Plane on the same machine as your code and use the default port 49000 that X-Plane uses for UDP
xpc = XPlaneConnectX(ip='127.0.0.1', port=49000) 

xpc.subscribeDREFs(subscribed_drefs)
xpc.startRECORDING()
time.sleep(5)
recording = xpc.stopRECORDING()

print("stop")
