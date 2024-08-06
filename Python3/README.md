# XPlaneConnect2 - Python 3

This guide is for the Python3 version lof XPlaneConnect2. The code was developed using Python 3.12 and X-Plane 12.1. We tested our implementation on Ubuntu 22.04, macOS Sonoma, and Windows 11.

## Requirements
No plugins are required, only an installed copy of X-Plane 12 and Python 3. Additionally, it is necessary to explicitly "accept incoming connections" in the X-Plane Network settings. By default, it appears that this option is disabled. 

## Functionality
At the moment, the following functions are supported:
- listen to DataRefs
- write to (writable) DataRefs
- send commands to X-Plane
- pause and un-pause X-Plane (this is just a wrapper for the `sim/operation/pause_on` and `sim/operation/pause_off` commands)

A full list of DataRefs can be found in `/.../X-Plane 12/Resources/plugins/DataRefs.txt` and full list of commands in `/.../X-Plane 12/Resources/plugins/Commands.txt`.

## Usage
### Initialization
Make sure that you add the `XPlaneConnect2.py` to your code directory. To initialize an instance of the `XPlaneConnect2` object, you need to specify a list of DataRefs you want to observe alongside the frequency you want to observe them in the following format:
```
[['/the/first/dataref', freq1],
 ['/the/second/dataref',freq2,]
  ...
]
```
The following code shows a specific example, where the roll ($\phi$), pitch ($\theta$), and yaw ($\psi$) angles are observed at 10Hz.

```python
from XPlaneConnect2 import XPlaneConnect2

observed_drefs = [["sim/flightmodel/position/phi",10],
                  ["sim/flightmodel/position/theta",10],
                  ["sim/flightmodel/position/psi",10],
                 ]
xpc = XPlaneConnect2(observed_drefs)
```

At initialization of the `xpc` object, the request for the specified DataRefs and the frequency is made to X-Plane and the data that is subsequently received from X-Plane is processed.

> **Note**: Should your X-Plane machine run on a different machine and/or use a different port, you need to specify this with the keyword arguments `ip` and `port` when initializing the `XPlaneConnect2` object. E.g., `XPlaneConnect2(observed_drefs, ip='192.168.10.15', port=49007)` expects to find a running X-Plane instance at `192.168.10.15` on port 49007. Make sure that these ports are configured properly in your system's firewall.

### Reading DataRefs
The most up-to-date data is always stored in the `xpc.current_data` dictionary. The keys to this dictionary are the DataRef identifiers. If no value has been received for a DataRef, the value defaults to `None`. In addition, the timestamp is kept for when the last message from X-Plane was received. The following code shows how to access the current values as well as the timestamp, they were last updated.

```python
for k in xpc.current_data.keys():
    print(f"{k:<40} {xpc.current_data[k]['value']:<30} {xpc.current_data[k]['timestamp']}")
```
The output is:

```
sim/flightmodel/position/phi             -0.1530972570180893            2024-08-05 17:32:34.563019
sim/flightmodel/position/theta           2.090435028076172              2024-08-05 17:32:34.515170
sim/flightmodel/position/psi             115.21917724609375             2024-08-05 17:32:34.563025
```

### Writing DataRefs
Writing a DataRef is possible through the `XPlaneConnect2.send_dref` method. There are two positional keywords: `dref` and `value`. `dref` is a string of the DataRef that one wants to write to and `value` is the value one wants to set the aforementioned DataRef to.

> **Note**: Not all DataRefs are writiable. You can check whether a DataRef is writable in the full definitions of all DataRefs which can be found in `/.../X-Plane 12/Resources/plugins/DataRefs.txt`.

The following example shows how to set the pitch angle to $10^\circ$:

```python
xpc.set_dref('sim/flightmodel/position/theta',10.0)
```

### Sending Commands
X-Plane also defines a set of (mostly simulator-related) commands that are specified in `/.../X-Plane 12/Resources/plugins/Commands.txt`. In contrast to DataRefs, those commands do not require a value. 

The following example shows how to take a screenshot:

```python
xpc.send_cmnd('sim/operation/screenshot')
```

Screenshots are by default stored in `/.../X-Plane 12/Output/screenshots/`. 

### Pausing and Un-Pausing the Simulator
A common command is to pause and un-pause the simulator (or more specifically, its physics engine). While technically, the commands `sim/operation/pause_on` and `sim/operation/pause_off` accomplish this, we provide a wrapper for convenience. The following code example, pauses the simulator for 1s and then un-pauses the simulator again.

```python
import time

xpc.pause(True)
time.sleep(1)
xpc.pause(False)
```
# Full Example
A full example can be found in the `example.py` file.