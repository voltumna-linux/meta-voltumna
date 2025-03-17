require conf/machine/include/x86/x86-base.inc

# ttyS4 is J39 on the board
SERIAL_CONSOLES = "115200;ttyS4"

# Enable the kernel console on ttyS4
#APPEND += "console=tty0 console=ttyS4,115200n8"
APPEND += "console=ttyS0,115200n8 console=tty0"
MACHINE_FEATURES += "efi"
