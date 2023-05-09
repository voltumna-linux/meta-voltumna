#@TYPE: Machine
#@NAME: Naples

#@DESCRIPTION: Machine configuration for Naples systems

require conf/machine/include/tune-zen1.inc
require conf/machine/include/quartz.inc

MACHINEOVERRIDES =. "amd:"
ALLOW_EMPTY:${KERNEL_PACKAGE_NAME}-devicetree = "1"
MACHINE_FEATURES += "efi"
EFI_PROVIDER = ""
WKS_FILE ?= "grub-bootdisk.wks"
