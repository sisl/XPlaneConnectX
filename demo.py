from Python3.XPlaneConnectX import XPlaneConnectX
import time

xpc = XPlaneConnectX(ip='127.0.0.1', port=49000)

for i in range(25):
    xpc.sendCMND("sim/operation/screenshot")
    time.sleep(0.04)

xpc.sendCTRL(lat_control=0.0,       # yoke rotation neutral
             lon_control=0.0,       # yoke forward/backward neutral
             rudder_control=0.0,    # rudder neutral
             throttle=0.0,          # throttle 0
             gear=1,                # landing gear down
             flaps=1.0,             # flaps fully extended
             speedbrakes=0.0,       # no speedbrakes
             park_break=1.0)        # parking brake set

for i in range(125):
    xpc.sendCMND("sim/operation/screenshot")
    time.sleep(0.04)

