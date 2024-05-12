#@TYPE: Machine
#@NAME: Rome

#@DESCRIPTION: Machine configuration for Rome systems

require conf/machine/include/tune-zen2.inc
require conf/machine/include/quartz.inc

MACHINEOVERRIDES =. "amd:"
ALLOW_EMPTY:${KERNEL_PACKAGE_NAME}-devicetree = "1"
MACHINE_FEATURES += "efi"
EFI_PROVIDER = ""
WKS_FILE ?= "grub-bootdisk.wks"
QEMU_EXTRAOPTIONS_zen2 = " -cpu EPYC-Rome-v2"
