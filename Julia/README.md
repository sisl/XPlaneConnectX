# XPlaneConnectX - Julia

This guide is for the Julia version of XPlaneConnectX. The code was developed using Julia 1.10 and X-Plane 12.1. We tested our implementation on Ubuntu 22.04, macOS Sonoma, and Windows 11. We also suspect that our code will work with X-Plane 11 since the UDP interface does not seem to have changed.


## Requirements
No plugins are required, only an installed copy of X-Plane 12 and Julia. Additionally, it is necessary to explicitly "accept incoming connections" in the X-Plane network settings. By default, it appears that this option is disabled. 

## Installation
There is no specific package installation required for our code as we are only using the standard library of Julia. You only need to make sure the file `XPlaneConnectX.jl` file is visible to your code and include it:

```julia
include("XPlaneConnectX.jl")
```

## Functionality
At the moment, the following functions are supported:
- [`subscribeDREFs`](#subscribing-to-datarefs)
- [`getDREF`](#reading-datarefs)
- [`sendDREF`](#sending-datarefs)
- [`sendCMND`](#sending-commands)
- [`getPOSI`](#reading-the-position-of-an-aircraft)
- [`sendPOSI`](#setting-an-aircraft-position)
- [`sendCTRL`](#controlling-the-aircraft)
- [`pauseSIM`](#pausing-and-un-pausing-the-simulator)

A full list of DataRefs can be found in `/.../X-Plane 12/Resources/plugins/DataRefs.txt` and full list of commands in `/.../X-Plane 12/Resources/plugins/Commands.txt`.

> **Note**: The names of the functions is taken from the original `XPlaneConnect`. However, some functions have slightly different arguments or return a slightly different set of values than the original `XPlaneConnect`. Where applicable, we note this in the API.

## Usage and API
### Initialization
```julia
XPlaneConnectX(; ip::String="127.0.0.1", port::Int64=49000)
```

Initialize an `XPlaneConnectX` instance.

#### Arguments
- `ip::String="127.0.0.1"`: IP address where X-Plane can be found. Defaults to '127.0.0.1'.
- `port::Int=49000`: Port to communicate with X-Plane. This can be found and changed in the X-Plane network settings. Defaults to 49000.

> **Note**: If not running on the same machine, make sure your firewall is correctly configured to send UDP packets to X-Plane and receive packets from X-Plane.

#### Returns
An instance of `XPlaneConnectX` initialized with a UDP socket, the provided IP address, and port.

#### Examples
```julia
xpc = XPlaneConnectX() # Uses default IP and port
xpc = XPlaneConnectX(ip="192.168.1.10", port=50000) # Custom IP and port
print(xpc.current_dref_values)  #prints the most recent values received from the subsribed to DataRefs
```

### Subscribing to DataRefs
```julia
subscribeDREFs(xpc::XPlaneConnectX, subscribed_drefs::Vector{Tuple{String, Int64}})
```

Permanently subscribe to a list of DataRefs with a certain frequency. This method is preferred for obtaining the most up-to-date values for DataRefs that will be used frequently during the runtime of your code. Examples include position, velocity, or attitude. The data will be asynchronously received and processed, unlike the synchronous `getDREF` or `getPOSI` methods. The most recent value for each subscribed DataRef is stored in `xpc.current_dref_values`, which is a dictionary with DataRefs as keys. Each entry contains another dictionary with the keys `"value"` and `"timestamp"` representing the most recent value and the time it was received, respectively. A full list of DataRefs can be found in `/.../X-Plane 12/Resources/plugins/DataRefs.txt`. Plugins can define their own DataRefs that you can subscribe to as well. Often, those definitions are stored within the plugin's directory itself.

> **Note**: This function does not exist in the original `XPlaneConnect`, however, for code performance, this functionality can be helpful.

#### Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` to which the DataRefs will be subscribed.
- `subscribed_drefs::Vector{Tuple{String, Int64}}`: List of (DataRef, frequency) tuples to be permanently observed.

#### Example
```julia
xpc = XPlaneConnectX()
subscribeDREFs(xpc, [("sim/cockpit2/controls/brake_fan_on", 2),  # brake fan at 2Hz
                     ("sim/flightmodel/position/y_agl", 10)])    # altitude above ground at 10Hz
print(xpc.current_dref_values)
```

### Reading DataRefs
```julia
getDREF(xpc::XPlaneConnectX, dref::String) -> Float32
```

Gets the current value of a DataRef. This function is intended for one-time use due to its synchronous nature. I.e., calling `getDREF` will block your code until the value is received. For DataRefs with frequent use, consider using the `subscribeDREFs` function. A full list of DataRefs can be found in `/.../X-Plane 12/Resources/plugins/DataRefs.txt`. Plugins can define their own DataRefs that you can subscribe to as well. Often, those definitions are stored within the plugin's directory itself.

#### Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` to perform the query.
- `dref::String`: DataRef to be queried.

#### Returns
- `Float32`: The value of the DataRef `dref`.

#### Example
```julia
xpc = XPlaneConnectX()
value = getDREF(xpc, "sim/cockpit2/controls/brake_fan_on")
```

### Sending DataRefs
```julia
sendDREF(xpc::XPlaneConnectX, dref::String, value::Any)
```

Writes a value to the specified DataRef, provided that the DataRef is writable. A full list of DataRefs can be found in `/.../X-Plane 12/Resources/plugins/DataRefs.txt`. Plugins can define their own DataRefs that you can subscribe to as well. Often, those definitions are stored within the plugin's directory itself.

#### Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` used to send the data.
- `dref::String`: The DataRef to be changed.
- `value::Any`: The value to which the DataRef should be set. This is converted into a `Float32` for the UDP transmission.

#### Example
```julia
xpc = XPlaneConnectX()
sendDREF(xpc, "sim/cockpit/electrical/landing_lights_on", 1.0)  # Turn on the landing lights
```

### Sending Commands
```julia
sendCMND(xpc::XPlaneConnectX, command::String)
```

Sends simulator commands to the simulator. These commands are not for (only) controlling airplanes but for operating the simulator itself (e.g., closing X-Plane or taking a screenshot). A full list of all commands can be found in `/.../X-Plane 12/Resources/plugins/Commands.txt`. Addons for X-Plane can define additional commands that can be triggered through this interface as well.

#### Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` used to send the command.
- `command::String`: The command to be executed by the simulator.

#### Example
```julia
xpc = XPlaneConnectX()
sendCMND(xpc, "sim/operation/quit")  # Example command to close X-Plane
```

### Setting an Aircraft Position
```julia
sendPOSI(xpc::XPlaneConnectX; lat::Any, lon::Any, elev::Any, phi::Any, theta::Any, psi_true::Any, ac::Int=0)
```

Sets the global position and attitude of an airplane. This is the only method to set the latitude and longitude of an airplane, as these DataRefs are not writable. Ensure that the latitude and longitude values are provided as `Float64` since a `Float32` is not accurate enough for precise placement of the aircraft.

#### Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX` used to send the position data.
- `lat::Any`: Latitude in degrees. For precise placement, this should be a `Float64`.
- `lon::Any`: Longitude in degrees. For precise placement, this should be a `Float64`.
- `elev::Any`: Altitude above mean sea level in meters. This should be a `Float64`.
- `phi::Any`: Roll angle in degrees. This should be a `Float32`.
- `theta::Any`: Pitch angle in degrees. This should be a `Float32`.
- `psi_true::Any`: True heading (not magnetic) in degrees. This should be a `Float32`.
- `ac::Int=0`: Index of the aircraft to set the position for. `0` refers to the ego aircraft. Defaults to `0`.

> **Note**: The original `XPlaneConnect` also specifies a landing gear position.

#### Example
```julia
xpc = XPlaneConnectX()
sendPOSI(xpc, 37.77493142132, -122.4194526721, 500.0, 0.0, 0.0, 90.0)
```

### Reading the Position of an Aircraft
```julia
getPOSI(xpc::XPlaneConnectX) -> Tuple{Float64, Float64, Float64, Float32, Float32, Float32, Float32, Float32, Float32, Float32, Float32, Float32}
```

Gets the global position of the ego aircraft. If this information is needed frequently, consider using the permanently observed DataRefs set up when initializing the `XPlaneConnectX` object.

The function retrieves the following values, which correspond to DataRefs:

- `sim/flightmodel/position/longitude`
- `sim/flightmodel/position/latitude`
- `sim/flightmodel/position/elevation`
- `sim/flightmodel/position/y_agl`
- `sim/flightmodel/position/phi`
- `sim/flightmodel/position/theta`
- `sim/flightmodel/position/true_psi`
- `sim/flightmodel/position/local_vx`
- `sim/flightmodel/position/local_vy`
- `sim/flightmodel/position/local_vz`
- `sim/flightmodel/position/Prad`
- `sim/flightmodel/position/Qrad`
- `sim/flightmodel/position/Rrad`

#### Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX`.

> **Note**: The original aircraft also allows to set the aircraft index. This version currently does not support this functionality and all data that is returned is of the ego-aircraft only.

#### Returns
- A tuple containing:
  - `Float64`: Latitude in degrees
  - `Float64`: Longitude in degrees
  - `Float64`: Elevation above mean sea level in meters
  - `Float32`: Elevation above the terrain in meters
  - `Float32`: Roll angle in degrees
  - `Float32`: Pitch angle in degrees
  - `Float32`: True heading (not magnetic) in degrees
  - `Float32`: Speed in east direction in meters per second
  - `Float32`: Speed in up direction in meters per second
  - `Float32`: Speed in south direction in meters per second
  - `Float32`: Roll rate in radians per second
  - `Float32`: Pitch rate in radians per second
  - `Float32`: Yaw rate in radians per second

> **Note**: The original `XPlaneConnect` returns the following values: latitude, longitude, altitude above MSL, pitch angle, roll angle, true heading, and the position of the landing gear. 

#### Example
```julia
xpc = XPlaneConnectX()
lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r = getPOSI(xpc)
```

### Controlling the Aircraft
```julia
sendCTRL(xpc::XPlaneConnectX; lat_control::Number, lon_control::Number, rudder_control::Number, throttle::Number, gear::Signed, flaps::Number, speedbrakes::Number, park_brake::Number)
```

Sends basic control inputs to the ego aircraft. For more fine-grained control, refer to the DataRefs that can be set using the `setDREF` method.

#### Arguments
- `xpc::XPlaneConnectX`: An instance of `XPlaneConnectX`.
- `lat_control::Number`: Lateral pilot input, representing yoke rotation or side stick left/right position. Ranges from `[-1, 1]`.
- `lon_control::Number`: Longitudinal pilot input, representing yoke or side stick forward/backward position. Ranges from `[-1, 1]`.
- `rudder_control::Number`: Rudder pilot input. Ranges from `[-1, 1]`.
- `throttle::Number`: Throttle position. Ranges from `[-1, 1]`, where `-1` indicates full reverse thrust and `1` indicates full forward thrust.
- `gear::Signed`: Requested gear position. `0` corresponds to gear up, and `1` corresponds to gear down.
- `flaps::Number`: Requested flaps position. Ranges from `[0, 1]`.
- `speedbrakes::Number`: Requested speedbrakes position. Possible values are `-0.5` (armed) and the range from `0` (retracted) to `1` (fully deployed).
- `park_brake::Number`: Requested park brake ratio. Ranges from `[0, 1]`.

> **Note**: The original aircraft also allows to set the aircraft index. This version currently does not support this functionality. All controls are regarding the ego aircraft.

#### Example
```julia
xpc = XPlaneConnectX()
sendCTRL(xpc, lat_control=-0.2, lon_control=0.0, rudder_control=0.2, throttle=0.8, gear=1, flaps=0.5, speedbrakes=0, park_brake=0)
```

### Pausing and Un-Pausing the Simulator
```julia
pauseSIM(xpc::XPlaneConnectX, set_pause::Bool)
```

Pauses or unpauses the simulator based on the given input.

#### Arguments
- `xpc::XPlaneConnectX`: The `XPlaneConnectX` object used to interact with the simulator.
- `set_pause::Bool`: If `true`, the simulator is paused. If `false`, the simulator is unpaused.

#### Example
```julia
xpc = XPlaneConnectX()
pauseSIM(xpc, true)  # Pauses the simulator
pauseSIM(xpc, false) # Unpauses the simulator
```

## Full Example
The code for a full exmple can be found in [example.jl](./example.jl). Before starting the code, make sure you have loaded the Cessna 172 aircraft at any airport.