GRUB_BUILDIN:append = " reboot echo net efinet tftp"

PROVIDES += "virtual/bootloader"

RDEPENDS:${PN} += "grub-bootconf"
