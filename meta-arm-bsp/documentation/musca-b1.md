# Musca B1

## Overview
For a description of the hardware, go to
https://developer.arm.com/tools-and-software/development-boards/iot-test-chips-and-boards/musca-b-test-chip-board

For current supported hardware by Zephyr, go to
https://docs.zephyrproject.org/2.3.0/boards/arm/v2m_musca/doc/index.html

For emulated hardware, go to
https://www.qemu.org/docs/master/system/arm/musca.html

## Building
In the local.conf file, MACHINE should be set as follows:
MACHINE ?= "musca-b1"

To build for Zephyr:
```bash$ bitbake-layers layerindex-fetch meta-zephyr```
```bash$ bitbake zephyr-philosophers```

To build the trusted firmware-m (and not Zephyr):
```bash$ bitbake trusted-firmware-m```

## Running
To run Zephyr on the QEMU based machine, execute the following command
```bash$ runqemu qemu-musca-b1```
