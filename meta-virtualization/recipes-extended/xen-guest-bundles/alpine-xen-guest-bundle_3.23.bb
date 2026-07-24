# alpine-xen-guest-bundle_3.23.bb
# ===========================================================================
# Alpine Linux minirootfs as a Xen guest via the import system
# ===========================================================================
#
# This recipe demonstrates xen-guest-bundle's import system for 3rd-party
# guests. It fetches the Alpine Linux minirootfs tarball, converts it to
# an ext4 disk image at build time, and packages it as a Xen guest bundle.
#
# Usage in image recipe (e.g., xen-image-minimal.bb):
#   IMAGE_INSTALL:append:pn-xen-image-minimal = " alpine-xen-guest-bundle"
#
# The guest uses the shared host kernel (KERNEL_IMAGETYPE from
# DEPLOY_DIR_IMAGE), so a compatible kernel must be built for the
# same MACHINE.

SUMMARY = "Alpine Linux Xen guest bundle"
DESCRIPTION = "Packages Alpine Linux minirootfs as an autostarting Xen \
               PV guest. Uses the xen-guest-bundle import system to \
               convert the tarball into an ext4 disk image."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

inherit xen-guest-bundle

S = "${UNPACKDIR}"

ALPINE_VERSION = "3.23.3"
ALPINE_ARCH = "aarch64"
ALPINE_ARCH:x86-64 = "x86_64"

SRC_URI = "https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz;subdir=alpine-rootfs;name=${ALPINE_ARCH}"
SRC_URI[aarch64.sha256sum] = "f219bb9d65febed9046951b19f2b893b331315740af32c47e39b38fcca4be543"
SRC_URI[x86_64.sha256sum] = "42d0e6d8de5521e7bf92e075e032b5690c1d948fa9775efa32a51a38b25460fb"

# Guest definition: name is "alpine", autostart, external (no Yocto image dep)
XEN_GUEST_BUNDLES = "alpine:autostart:external"

# Import: extract tarball directory → ext4 image
XEN_GUEST_SOURCE_TYPE[alpine] = "rootfs_dir"
XEN_GUEST_SOURCE_FILE[alpine] = "alpine-rootfs"
XEN_GUEST_IMAGE_SIZE[alpine] = "128"

# Guest parameters
XEN_GUEST_MEMORY[alpine] = "256"
# Use init=/bin/sh — Alpine minirootfs doesn't include openrc which
# /sbin/init symlinks to. The minirootfs is container-oriented, not
# a full bootable system.
XEN_GUEST_EXTRA[alpine] = "root=/dev/xvda ro console=hvc0 init=/bin/sh"
