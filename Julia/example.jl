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
]

# this assumes you are running X-Plane on the same machine as your code and use the default port 49000 that X-Plane uses for UDP
xpc = XPlaneConnectX(ip="127.0.0.1", port=49000) 

# subscribe to datarefs
subscribeDREFs(xpc,subscribed_drefs)    # the current values are stored in xpc.current_dref_values

# Set the airplane's location to Palo Alto (KPAO), runway 31.
lat, lon, elev = 37.458194732666016, -122.11215209960938, 2.239990472793579
phi, theta, psi = 0, 0, 321.83612060546875

pauseSIM(xpc,true) # for "long jumps" you want to pause the simulator
sendPOSI(xpc,
         lat=lat,       #latitude in degrees
         lon=lon,       #longitude in degrees 
         elev=elev,     #altitude above mean sea level in meters
         phi=phi,       #roll angle in degrees
         theta=theta,   #pitch angle in degrees
         psi_true=psi)  #true (not magnetic) heading

println("Waiting for X-Plane to load scenery...")
sleep(30)  # X-Plane needs time to load the new scenery for "long jumps"

pauseSIM(xpc,false)

# Turn the landing lights on and veryify that they are on
sendDREF(xpc,"sim/cockpit/electrical/landing_lights_on",true)
println("Status of landing lights: ", getDREF(xpc,"sim/cockpit/electrical/landing_lights_on"))

# Increase throttle to taxi and compensate for torque with rudder. Also release parking brake.
sendCTRL(xpc,
         lat_control=0,        # yoke in neutral position
         lon_control=0,        # yoke in neutral position
         rudder_control=0.3,   # rudder
         throttle=0.2,         # throttle
         gear=1,               # landing gear down
         flaps=0,              # no flaps
         speedbrakes=0,        # no speedbrakes
         park_brake=0,         # parking brake released
        )   

# Taxi for 10s and print the observed DataRefs once per second
for i=1:10
    print_state(xpc.current_dref_values)
    sleep(1)
end

sendCTRL(xpc,lat_control=0,lon_control=0,rudder_control=0,throttle=0,gear=1,flaps=0,speedbrakes=0,park_brake=1)   # no throttle, parking brake set      

println("The current position is: ", getPOSI(xpc)) 

sleep(5)

sendCMND(xpc,"sim/operation/reset_flight")   # reset the flight