# This example is designed for the default Cessna 172. Before starting this script, make sure to load the C172 at any airport.

import time
from XPlaneConnectX import XPlaneConnectX

# helper function to print state
def print_state(state):
    print('-'*98)
    for k in state.keys():
        print(f"{k:<40} {state[k]['value']:<30} {state[k]['timestamp']}")

observed_drefs=[["sim/flightmodel/position/groundspeed",10],    # ground speed in m/s at 10Hz
                ["sim/flightmodel/position/mag_psi ",10],       # magnetic heading in degrees at 10Hz
                ]   
   
xpc = XPlaneConnectX(observed_drefs)

time.sleep(0.5)     # this is just a safety buffer    

# Set the airplane's location to Palo Alto (KAPO), runway 31.
lat, lon, elev = 37.458194732666016, -122.11215209960938, 2.239990472793579
phi, theta, psi = 0,0, 321.83612060546875

xpc.pause(True) # for "long jumps" you want to pause the simulator
xpc.sendPOSI(lat,lon,elev,phi,theta,psi)
time.sleep(2)  # X-Plane needs time to load the new scenery for "long jumps"
xpc.pause(False)

# Turn the landing lights on and veryify that they are on
xpc.sendDREF('sim/cockpit/electrical/landing_lights_on',True)
print(f"Status of landing lights: {xpc.getDREF('sim/cockpit/electrical/landing_lights_on')}")

# Increase throttle to taxi and compensate for torque with rudder. Also release parking brake.
xpc.sendCTRL(lat_control=0,         # yoke in neutral position
             lon_control=0,         # yoke in neutral position
             rudder_control=-0.3,   # rudder
             throttle=0.2,          # throttle
             gear=1,                # landing gear down
             flaps=0,               # no flaps
             speedbrakes=0,         # no speedbrakes
             park_break=0,          # parking brake released
             )    

# Taxi for 10s and print the observed DataRefs once per second
for _ in range(10):
    print_state(xpc.current_dref_values)
    time.sleep(1)

xpc.sendCTRL(0,0,0,0,1,0,0,1)   # no throttle, parking brake set      

print(f"The current position is: {xpc.getPOSI()}") 

time.sleep(5)

# Take a screenshot
xpc.sendCMND('sim/operation/reset_flight')   # reset the flight

