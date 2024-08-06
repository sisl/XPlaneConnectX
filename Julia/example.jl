using Printf

# import the XPlaneConnect2 code
include("XPlaneConnect2.jl")

# helper function to print state
function print_state(state)
    println("-"^98)
    for k in keys(state)
        println(@sprintf("%-40s %-30s %s", k, state[k]["value"], state[k]["timestamp"]))
    end
end

observed_drefs = [
    ("sim/flightmodel/position/phi", 10),   # roll angle
    ("sim/flightmodel/position/theta", 10), # pitch angle
    ("sim/flightmodel/position/psi", 10),   # yaw angle
]

xpc = XPlaneConnect2(observed_drefs)

sleep(0.5)          # this is just a safety buffer    

ldg_light = true    # we want to toggle the landing light at 1s intervals

while true
    global ldg_light
    print_state(xpc.current_data)   # print the current observed drefs
    set_dref(xpc, "sim/cockpit/electrical/landing_lights_on", ldg_light)    # toggle the landing lights
    ldg_light = !ldg_light  
    send_cmnd(xpc, "sim/operation/screenshot")  # take a screenshot (screenshots are stored in /.../X-Plane 12/Output/screenshots)
    sleep(1)
end