import time
from XPlaneConnect2 import XPlaneConnect2

# helper function to print state
def print_state(state):
    print('-'*98)
    for k in state.keys():
        print(f"{k:<40} {state[k]['value']:<30} {state[k]['timestamp']}")
        
xpc = XPlaneConnect2(observed_drefs=[["sim/flightmodel/position/phi",10],
                                       ["sim/flightmodel/position/theta",10],
                                       ["sim/flightmodel/position/psi",10],
                                       ["sim/flightmodel/position/P",10],
                                       ["sim/flightmodel/position/Q",10],
                                       ["sim/flightmodel/position/R",10],
                                       ["sim/flightmodel/position/y_agl",10],
                                        ])

time.sleep(1)
ldg_light = True

while True:
    print_state(xpc.current_data)
    xpc.set_dref('sim/cockpit/electrical/landing_lights_on',ldg_light)
    ldg_light = not ldg_light
    xpc.send_cmnd('sim/operation/screenshot')
    time.sleep(1)