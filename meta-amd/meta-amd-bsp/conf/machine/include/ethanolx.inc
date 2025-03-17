require conf/machine/include/x86/x86-base.inc

# Setup a getty on all serial ports
SERIAL_CONSOLES = "115200;ttyS0"

# Enable the kernel console on ttyS0
APPEND += "console=tty0 console=ttyS0,115200n8"

MACHINE_FEATURES += "efi"
