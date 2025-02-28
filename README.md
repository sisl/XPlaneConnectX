# XPlaneConnectX

In light of issues that the original `XPlaneConnect` seems to have with X-Plane 12 (especially on Ubuntu and macOS), this UDP-based script provides a similar interface to X-Plane as the original `XPlaneConnect`, but does not rely on a plugin (and also does not share any code with `XPlaneConnect`). 

At the moment, we provide implementations in Python 3 and Julia. The code was developed using Python 3.10, Julia 1.10, and X-Plane 12.1. We tested our code on Ubuntu 22.04, macOS Sonoma, and Windows 11. While we haven't tested the compatibility for any X-Plane versions <12.1, we suspect compatiblity at least with X-Plane 11 since the UDP interface does not seem to have changed signifcantly.

> **Note**: You **DO NOT** need to install a pre-compiled plugin (i.e., an `.xpl` file you copy to the plugins directory of your X-Plane installation) for `XPlaneConnectX` as we use the built-in UDP feature of X-Plane.

# Quick Start
Instead of turning our code into packages, we decided to leave them as standalone files that only rely on each language's standard library to facilitate the extension of the code for individual research needs. Furthermore, we use as much of the original synthax of `XPlaneConenct` as possible to allow for an easy transition of legacy users of `XPlaneConnect`. Differences to the functionality of `XPlaneConnect` is documented in the API for each function.

The following functions are currently supported (the links take you to the language-specific documentation):
- `subscribeDREFs` [[Py]](./Python3/README.md#subscribing-to-datarefs)/[[Jl]](./Julia/README.md#subscribing-to-datarefs)
- `getDREF` [[Py]](./Python3/README.md#reading-datarefs)/[[Jl]](./Julia/README.md#reading-datarefs)
- `sendDREF` [[Py]](./Python3/README.md#sending-datarefs)/[[Jl]](./Julia/README.md#sending-datarefs)
- `sendCMND` [[Py]](./Python3/README.md#sending-commands)/[[Jl]](./Julia/README.md#sending-commands)
- `getPOSI` [[Py]](./Python3/README.md#reading-the-position-of-an-aircraft)/[[Jl]](./Julia/README.md#reading-the-position-of-an-aircraft)
- `sendPOSI` [[Py]](./Python3/README.md#setting-an-aircraft-position)/[[Jl]](./Julia/README.md#setting-an-aircraft-position)
- `sendCTRL` [[Py]](./Python3/README.md#controlling-the-aircraft)/[[Jl]](./Julia/README.md#controlling-the-aircraft)
- `pauseSIM` [[Py]](./Python3/README.md#pausing-and-un-pausing-the-simulator)/[[Jl]](./Julia/README.md#pausing-and-un-pausing-the-simulator)


> **Before your start**: Ensure that X-Plane accepts incoming connections. For X-Plane 12, this seems to be disabled by default, but can be changed at the bottom of the network settings menu in X-Plane.

The following minimalistic example shows how to fully extend the flaps.

In Python:
```python
from XPlaneConnectX import XPlaneConnectX # assumes you have XPlaneConnectX.py in same directory

xpc = XPlaneConnectX()  # equivalent to XPlaneConnectX(ip='127.0.0.1',port=49000)

xpc.sendCTRL(lat_control=0.0,       # yoke rotation neutral
             lon_control=0.0,       # yoke forward/backward neutral
             rudder_control=0.0,    # rudder neutral
             throttle=0.0,          # throttle 0
             gear=1,                # landing gear down
             flaps=1.0,             # flaps fully extended
             speedbrakes=0.0,       # no speedbrakes
             park_brake=1.0)        # parking brake set
```

In Julia:
```julia
include("XPlaneConnectX.jl") # assumes you have XPlaneConnectX.jl in same directory

xpc = XPlaneConnectX()  # equivalent to XPlaneConnectX(ip='127.0.0.1',port=49000)

sendCTRL(xpc,                   # XPlaneConnectX struct
         lat_control=0.0,       # yoke rotation neutral
         lon_control=0.0,       # yoke forward/backward neutral
         rudder_control=0.0,    # rudder neutral
         throttle=0.0,          # throttle 0
         gear=1,                # landing gear down
         flaps=1.0,             # flaps fully extended
         speedbrakes=0.0,       # no speedbrakes
         park_brake=1.0)        # parking brake set
```

The resulting output:
![XPlaneConnectX Demo](xplaneconnectx.gif)

In addition, please also see the full example in [Python](./Python3/example.py) and [Julia](./Julia/example.jl) demonstrating more functions.

# Detailed Guides

There is a detailed guide for the Python and the Julia version in the respective sub-directories:
- [Python Guide](./Python3/README.md)
- [Julia Guide](./Julia/README.md)

# Contributing and Feature Requests

Contributions are always welcome! If you have any improvements or new features, feel free to make a pull request. If you have an idea for a useful new feature/functionality, please create an issue and label it with the `feature request` label.

# Citation
If you enjoy using `XPlaneConnectX`, please leave a star. If you use our software for your research, please use the following citation:

```
@misc{XPlaneConnectX,
  author       = {Marc R. Schlichting},
  title        = {XPlaneConnectX},
  year         = {2024},
  url          = {https://github.com/sisl/XPlaneConnectX},
  note         = {Accessed: YYYY-MM-DD}
}
```
