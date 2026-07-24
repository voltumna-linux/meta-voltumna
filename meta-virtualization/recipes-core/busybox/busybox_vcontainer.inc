# Busybox configuration for vcontainer (vdkr/vpdmn)
#
# These utilities are required by the vcontainer initramfs scripts
# for data transfer between QEMU guest and host via serial console.

FILESEXTRAPATHS:prepend := "${THISDIR}/busybox:"

SRC_URI += "file://utils.cfg"
