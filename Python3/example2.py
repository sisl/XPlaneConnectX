# This example is designed for the default Cessna 172. Before starting this script, make sure to load the C172 at any airport.

import time
from XPlaneConnectX import XPlaneConnectX

# helper function to print state
# def print_state(state):
#     print('-'*98)
#     for k in state.keys():
#         print(f"{k:<40} {state[k]['value']:<30} {state[k]['timestamp']}")

subscribed_drefs=[("sim/flightmodel/position/groundspeed",10),   # ground speed in m/s at 10Hz
                  ("sim/flightmodel/position/mag_psi",10),       # magnetic heading in degrees at 10Hz
                 ]   

# this assumes you are running X-Plane on the same machine as your code and use the default port 49000 that X-Plane uses for UDP
xpc = XPlaneConnectX(ip='192.168.0.11', port=49000) 

# subscribe to datarefs
xpc.subscribeDREFs(subscribed_drefs)    # the current values are stored in xpc.current_dref_values


# Taxi for 10s and print the observed DataRefs once per second
for i in range(10):
    print(xpc.current_dref_values)
    time.sleep(1)


