require conf/machine/include/x86/x86-base.inc

SERIAL_CONSOLES = "115200;ttyS4 115200;ttyS5"

APPEND += "console=tty0 console=ttyS4,115200n8"

MACHINE_FEATURES += "efi"
