import time
from XPlaneConnect2 import XPlaneConnect2

# helper function to print state
def print_state(state):
    print('-'*98)
    for k in state.keys():
        print(f"{k:<40} {state[k]['value']:<30} {state[k]['timestamp']}")

observed_drefs=[["sim/flightmodel/position/phi",10],     # roll angle
                ["sim/flightmodel/position/theta",10],   # pitch angle
                ["sim/flightmodel/position/psi",10],     # yaw angle
                ]   
   
xpc = XPlaneConnect2(observed_drefs)

time.sleep(0.5)     # this is just a safety buffer    

ldg_light = True    # we want to toggle the landing light at 1s intervals

while True:
    print_state(xpc.current_data)       # print the current observed drefs
    xpc.set_dref('sim/cockpit/electrical/landing_lights_on',ldg_light)  # toggle the landing lights
    ldg_light = not ldg_light
    xpc.send_cmnd('sim/operation/screenshot')   # take a screenshot (screenshots are stored in /.../X-Plane 12/Output/screenshots)
    time.sleep(1)