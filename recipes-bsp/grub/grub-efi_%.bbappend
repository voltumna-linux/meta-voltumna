GRUB_BUILDIN:append = " reboot echo net efinet tftp"

PROVIDES += "virtual/bootloader"

DEPENDS:class-target += "grub-bootconf"
