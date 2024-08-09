# XPlaneConnectX - Python 3

This guide is for the Python version of XPlaneConnectX. The code was developed using Python 3.10 and X-Plane 12.1. We tested our implementation on Ubuntu 22.04, macOS Sonoma, and Windows 11.

## Requirements
No plugins are required, only an installed copy of X-Plane 12 and Python. Additionally, it is necessary to explicitly "accept incoming connections" in the X-Plane Network settings. By default, it appears that this option is disabled. 

## Installation
There is no installation required. You only need to make sure the file `XPlaneConnectX.py` file is visible to your code and import the `XPlaneConnectX` object:

```python
from XPlaneConnectX import XPlaneConnectX
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
```python
XPlaneConnectX(ip:str='127.0.0.1', port:int=49000)
```

Initialize an `XPlaneConnectX` instance.

#### Arguments
- `ip::String="127.0.0.1"`: IP address where X-Plane can be found. Defaults to '127.0.0.1'.
- `port::Int=49000`: Port to communicate with X-Plane. This can be found and changed in the X-Plane network settings. Defaults to 49000.

> **Note**: If not running on the same machine, make sure your firewall is correctly configured to send UDP packets to X-Plane and receive packets from X-Plane.

#### Returns
An instance of `XPlaneConnectX` initialized with a UDP socket, the provided IP address, and port.

#### Examples
```python
xpc = XPlaneConnectX() # Uses default IP and port
xpc = XPlaneConnectX(ip="192.168.1.10", port=50000) # Custom IP and port
```

### Subscribing to DataRefs
```python
subscribeDREFs(subscribed_drefs:list[Tuple[str,int]]) -> None
```

Permanently subscribe to a list of DataRefs with a certain frequency. This method is preferred for obtaining the most up-to-date values for DataRefs that will be used frequently during the runtime of your code. Examples include position, velocity, or attitude. The data will be asynchronously received and processed, unlike the synchronous `getDREF` or `getPOSI` methods. The most recent value for each subscribed DataRef is stored in `xpc.current_dref_values`, which is a dictionary with DataRefs as keys. Each entry contains another dictionary with the keys `"value"` and `"timestamp"` representing the most recent value and the time it was received, respectively.

> **Note**: This function does not exist in the original XPlaneConnect, however, for code performance, this functionality can be helpful.

#### Arguments
- `subscribed_drefs:list[Tuple[str,int]]`: List of (DataRef, frequency) tuples to be permanently observed.

#### Example
```python
xpc = XPlaneConnectX()
xpc.subscribeDREFs([("sim/cockpit2/controls/brake_fan_on", 2), ("sim/flightmodel/position/y_agl", 10)])
print(xpc.current_dref_values)  #prints the most recent values received from the subsribed to DataRefs
```

### Reading DataRefs
```python
getDREF(dref:str) -> float
```

Gets the current value of a DataRef. This function is intended for one-time use. For DataRefs with frequent use, consider using the permanently observed DataRefs set up when initializing the `XPlaneConnectX` object.

#### Arguments
- `dref:str`: DataRef to be queried.

#### Returns
- `float`: The value of the DataRef `dref`.

#### Example
```python
xpc = XPlaneConnectX()
value = xpc.getDREF("sim/cockpit2/controls/brake_fan_on")
```

### Sending DataRefs
```python
sendDREF(dref:str, value:float) -> None
```

Writes a value to the specified DataRef, provided that the DataRef is writable.

#### Arguments
- `dref:str`: The DataRef to be changed.
- `value:float`: The value to which the DataRef should be set. This is converted into a single-precision float for the UDP transmission.

#### Example
```python
xpc = XPlaneConnectX()
xpc.sendDREF("sim/cockpit/electrical/landing_lights_on", 1.0)  # Turn on the landing lights
```

### Sending Commands
```python
sendCMND(command:str) -> None
```

Sends simulator commands to the simulator. These commands are not for (only) controlling airplanes but for operating the simulator itself (e.g., closing X-Plane or taking a screenshot). A full list of all commands can be found in `/.../X-Plane 12/Resources/plugins/Commands.txt`. Addons for X-Plane can define additional commands that can be triggered through this interface as well.

#### Arguments
- `command:str`: The command to be executed by the simulator.

#### Example
```python
xpc = XPlaneConnectX()
xpc.sendCMND("sim/operation/quit")  # close X-Plane
```

### Setting an Aircraft Position
```python
sendPOSI(lat:float, lon:float, elev:float, phi:float, theta:float, psi_true:float, ac:int=0) -> None
```

Sets the global position and attitude of an airplane. This is the only method to set the latitude and longitude of an airplane, as these DataRefs are not writable. Ensure that the latitude and longitude values are provided with enough decimals for a precise airplane placement.

#### Arguments
- `lat:float`: Latitude in degrees. 
- `lon:float`: Longitude in degrees.
- `elev:float`: Altitude above mean sea level in meters.
- `phi:float`: Roll angle in degrees. 
- `theta:float`: Pitch angle in degrees. 
- `psi_true:float`: True heading (not magnetic) in degrees. 
- `ac:int=0`: Index of the aircraft to set the position for. `0` refers to the ego aircraft. Defaults to `0`.

> **Note**: The original XPlaneConnect also specifies a landing gear position.

#### Example
```python
xpc = XPlaneConnectX()
xpc.sendPOSI(37.77493142132, -122.4194526721, 500.0, 0.0, 0.0, 90.0)
```

### Reading the Position of an Aircraft
```python
getPOSI() -> Tuple[float,float,float,float,float,float,float,float,float,float,float,float,float]
```

Gets the global position of the ego aircraft. If this information is needed frequently, consider using the permanently observed DataRefs set up when initializing the `XPlaneConnectX` object.

The function retrieves the following values, which correspond to DataRefs:

- `sim/flightmodel/position/longitude`
- `sim/flightmodel/position/latitude`
- `sim/flightmodel/position/elevation`
- `sim/flightmodel/position/y_agl`
- `sim/flightmodel/position/true_theta`
- `sim/flightmodel/position/true_psi`
- `sim/flightmodel/position/true_phi`
- `sim/flightmodel/position/local_vx`
- `sim/flightmodel/position/local_vy`
- `sim/flightmodel/position/local_vz`
- `sim/flightmodel/position/Prad`
- `sim/flightmodel/position/Qrad`
- `sim/flightmodel/position/Rrad`

> **Note**: The original aircraft also allows to set the aircraft index. This version currently does not support this functionality and all data that is returned is of the ego-aircraft only.

#### Returns
- A tuple containing:
  - `float`: Latitude in degrees
  - `float`: Longitude in degrees
  - `float`: Elevation above mean sea level in meters
  - `float`: Elevation above the terrain in meters
  - `float`: Roll angle in degrees
  - `float`: Pitch angle in degrees
  - `float`: True heading (not magnetic) in degrees
  - `float`: Speed in east direction in meters per second
  - `float`: Speed in up direction in meters per second
  - `float`: Speed in south direction in meters per second
  - `float`: Roll rate in radians per second
  - `float`: Pitch rate in radians per second
  - `float`: Yaw rate in radians per second

> **Note**: The original XPlaneConnect returns the following values: latitude, longitude, altitude above MSL, pitch angle, roll angle, true heading, and the position of the landing gear. 

#### Example
```python
xpc = XPlaneConnectX()
lat, lon, ele, y_agl, phi, theta, psi_true, vx, vy, vz, p, q, r = xpc.getPOSI()
```

### Controlling the Aircraft
```python
sendCTRL(self, lat_control:float, lon_control:float, rudder_control:float, throttle:float, gear:int, flaps:float, speedbrakes:float, park_break:float) -> None
```

Sends basic control inputs to the ego aircraft. For more fine-grained control, refer to the DataRefs that can be set using the `setDREF` method.

#### Arguments
- `lat_control:float`: Lateral pilot input, representing yoke rotation or side stick left/right position. Ranges from `[-1, 1]`.
- `lon_control:float`: Longitudinal pilot input, representing yoke or side stick forward/backward position. Ranges from `[-1, 1]`.
- `rudder_control:float`: Rudder pilot input. Ranges from `[-1, 1]`.
- `throttle:float`: Throttle position. Ranges from `[-1, 1]`, where `-1` indicates full reverse thrust and `1` indicates full forward thrust.
- `gear:int`: Requested gear position. `0` corresponds to gear up, and `1` corresponds to gear down.
- `flaps:float`: Requested flaps position. Ranges from `[0, 1]`.
- `speedbrakes:float`: Requested speedbrakes position. Possible values are `-0.5` (armed), `0` (retracted), and `1` (fully deployed).
- `park_break:float`: Requested park brake ratio. Ranges from `[0, 1]`.

> **Note**: The original aircraft also allows to set the aircraft index. This version currently does not support this functionality. All controls are regarding the ego aircraft.

#### Example
```python
xpc = XPlaneConnectX()
xpc.sendCTRL(lat_control=-0.2, lon_control=0.0, rudder_control=0.2, throttle=0.8, gear=1, flaps=0.5, speedbrakes=0, park_break=0)
```

### Pausing and Un-Pausing the Simulator
```python
pauseSIM(self, set_pause:bool) -> None
```
Pauses or unpauses the simulator based on the given input.

#### Arguments
- `set_pause:bool`: If `True`, the simulator is paused. If `False`, the simulator is unpaused.

#### Example
```python
xpc = XPlaneConnectX()
xpc.pauseSIM(True)  # Pauses the simulator
xpc.pauseSIM(False) # Unpauses the simulator
```

## Full Example
The code for a full exmple can be found in [example.py](./example.py). Before starting the code, make sure you have loaded the Cessna 172 aircraft at any airport.