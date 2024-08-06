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
    ("sim/flightmodel/position/phi", 10),
    ("sim/flightmodel/position/theta", 10),
    ("sim/flightmodel/position/psi", 10),
    ("sim/flightmodel/position/P", 10),
    ("sim/flightmodel/position/Q", 10),
    ("sim/flightmodel/position/R", 10),
    ("sim/flightmodel/position/y_agl", 10)
]

xpc = XPlaneConnect2(observed_drefs)

sleep(1)
ldg_light = true

while true
    global ldg_light
    print_state(xpc.current_data)
    set_dref(xpc, "sim/cockpit/electrical/landing_lights_on", ldg_light)
    ldg_light = !ldg_light
    send_cmnd(xpc, "sim/operation/screenshot")
    sleep(1)
end