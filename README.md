# XPlaneConnectX

In light of issues that the original `XPlaneConnect` seems to have with X-Plane 12 (especially with Ubuntu and macOS), this lightweight script provides a similar interface to read DataRefs, set DataRefs, and send commands as it is possible with the original `XPlaneConnect`. 

At the moment, we provide implementations in Python 3 and Julia. The code was developed using Python 3.10, Julia 1.10, and X-Plane 12.1. We tested our code on Ubuntu 22.04, macOS Sonoma, and Windows 11. While we haven't tested the compatibility for X-Plane versions <12.0, we suspect compatiblity at least with X-Plane 11 since the UDP interface does not seem to have changed signifcantly.

> **Note**: You **DO NOT** need to install a pre-compiled plugin (i.e., an `.xpl` file you copy to the plugins directory of your X-Plane installation) for `XPlaneConnectX` as we use the built-in UDP feature of X-Plane.

# Quick Start
Instead of turing our code in standalone packages, we decided to leave them as standalone files that only rely on each language's standard library to facilitate the extension of the code for individual research needs. Furthermore, we use as much of the original synthax of `XPlaneConenct` to allow for an easy transition of legacy users of `XPlaneConnect`.

The following functions are currently supported:
- `subscribeDREFs` [[Py]](./Python3/README.md#subscribing-to-datarefs)/[[Jl]](./Julia/README.md#subscribing-to-datarefs)
- `getDREF` [[py]](./Python3/README.md#reading-datarefs)/[[jl]](./Julia/README.md#reading-datarefs)
- `sendDREF` [[Py]](./Python3/README.md#sending-datarefs)/[[Jl]](./Julia/README.md#sending-datarefs)
- `sendCMND` [[Py]](./Python3/README.md#sending-commands)/[[Jl]](./Julia/README.md#sending-commands)
- `getPOSI` [[Py]](./Python3/README.md#reading-the-position-of-an-aircraft)/[[Jl]](./Julia/README.md#reading-the-position-of-an-aircraft)
- `sendPOSI` [[Py]](./Python3/README.md#setting-an-aircraft-position)/[[Jl]](./Julia/README.md#setting-an-aircraft-position)
- `sendCTRL` [[Py]](./Python3/README.md#controlling-the-aircraft)/[[Jl]](./Julia/README.md#controlling-the-aircraft)
- `pauseSIM` [[Py]](./Python3/README.md#pausing-and-un-pausing-the-simulator)/[[Jl]](./Julia/README.md#pausing-and-un-pausing-the-simulator)

The following minimalistic example shows how to fully extend the landing flaps.

In Python:
```python
from XPlaneConnectX import XPlaneConnectX

xpc = XPlaneConnectX(ip='127.0.0.1', port=49000)

xpc.sendCTRL(lat_control=0.0,       # yoke rotation neutral
             lon_control=0.0,       # yoke forward/backward neutral
             rudder_control=0.0,    # rudder neutral
             throttle=0.0,          # throttle 0
             gear=1,                # landing gear down
             flaps=1.0,             # flaps fully extended
             speedbrakes=0.0,       # no speedbrakes
             park_break=1.0)        # parking brake set
```

In Julia:
```julia
include("./Julia/XPlaneConnectX.jl")

xpc = XPlaneConnectX(ip="127.0.0.1", port=49000)

sendCTRL(xpc,                   # XPlaneConnectX struct
         lat_control=0.0,       # yoke rotation neutral
         lon_control=0.0,       # yoke forward/backward neutral
         rudder_control=0.0,    # rudder neutral
         throttle=0.0,          # throttle 0
         gear=1,                # landing gear down
         flaps=1.0,             # flaps fully extended
         speedbrakes=0.0,       # no speedbrakes
         park_break=1.0)        # parking brake set
```

The resulting output:
![XPlaneConnectX Demo](xplaneconnectx.gif)

# Detailed Guides

There is a detailed guide for the Python and the Julia version in the respective sub-directories:
- [Python Guide](./Python3/README.md)
- [Julia Guide](./Julia/README.md)

# Citation
If you use our software for your research, please leave us a star and use the following citation:

```
@misc{XPlaneConnect2,
  author       = {Marc R. Schlichting},
  title        = {XPlaneConnectX},
  year         = {2024},
  url          = {https://github.com/sisl/XPlaneConnectX},
  note         = {Accessed: YYYY-MM-DD}
}
```
