# XPlaneConnect2 

In light of issues that the original XPlaneConnect seems to have with X-Plane 12 (especially with Ubuntu and macOS), this lightweight script provides a similar interface to read DataRefs, set DataRefs, and send commands as it is possible with the original XPlaneConnect. 

At the moment, we provide implementations in Python 3 and Julia. The code was developed using Python 3.12, Julia 1.10, and X-Plane 12.1. We tested our code on Ubuntu 22.04, macOS Sonoma, and Windows 11. While we haven't tested the compatibility for X-Plane versions <12.0, we suspect compatiblity at least with X-Plane 11 since the UDP interface does not seem to have changed signifcantly.

> **Note**: You **DO NOT** need to install a pre-compiled plugin (i.e., an `.xpl` file you copy to the plugins directory of your X-Plane installation) for XPlaneConnect2 as we use the built-in UDP feature of X-Plane.

# Detailed Guides

There is a detailed guide for the Python and the Julia version in the respective sub-directories:
- [Python Guide](./Python3/README.md)
- [Julia Guide](./Julia/README.md)

# Citation
If you use our software for your research, please leave us a star and use the following citation:

```
@misc{XPlaneConnect2,
  author       = {Marc R. Schlichting},
  title        = {XPlaneConnect2},
  year         = {2024},
  url          = {https://github.com/sisl/XPlaneConnect2},
  note         = {Accessed: YYYY-MM-DD}
}
```
