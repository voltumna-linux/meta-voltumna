# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# vxn-dom0-common.inc -- shared body of the vxn Xen dom0 multiconfigs
# ============================================================================
# Everything the vxn dom0 images share, regardless of container-engine flavor
# (docker / podman) or arch. The per-flavor multiconfigs (vxn-<arch>.conf,
# vxn-podman-<arch>.conf) set only what actually differs -- MACHINE, TMPDIR, and
# the engine IMAGE_INSTALL line -- then `require` this file.
#
# This is required FROM a multiconfig, not from local.conf. A standard
# xen-image-minimal build never parses it, so ordinary Xen root filesystems are
# unaffected.

DISTRO = "poky"

# Base virtualization features + Xen + vxn (mirrors meta-virt-host.conf +
# xen-host.conf, minus the BBMULTICONFIG assignment which must not be set from
# inside a multiconfig).
DISTRO_FEATURES:append = " virtualization systemd seccomp vmsep vcontainer xen vxn"
INIT_MANAGER = "systemd"
PREFERRED_PROVIDER_virtual/runc ?= "runc"

# Opt-in: build axis into the dom0 for config-b (`axis run --policy vxn` running
# INSIDE dom0). Off by default to preserve the slimmed dom0; set
# VXN_INCLUDE_AXIS = "1" for a zero-setup config-b dom0. axis cross-compiles
# against dom0's exact sysroot, so there is no glibc/loader mismatch (unlike a
# host-built or musl-static binary scp'd in).
VXN_INCLUDE_AXIS ?= "0"
IMAGE_INSTALL:append:pn-xen-image-minimal = "${@oe.utils.conditional('VXN_INCLUDE_AXIS', '1', ' axis', '', d)}"

XEN_BOOT_MODE = "bios"
XEN_DOM0_NETWORK = "nat"

# Opt-in dom0 slimming for SDK distribution: the PV-only vxn dom0 needs no qemu
# HVM device model, EDK2 firmware, or GL stack (~530MB of the rootfs). Scoped to
# the vxn multiconfigs -- the standard xen-image-minimal build (main config)
# never parses the include, so ordinary Xen root filesystems are unaffected. Set
# VXN_SLIM_DOM0 = "0" to build the full dom0.
VXN_SLIM_DOM0 ?= "1"
require ${@oe.utils.conditional('VXN_SLIM_DOM0', '1', 'conf/distro/include/vxn-slim-dom0.inc', '', d)}

# dom0 hosts the podman/docker image store AND the ext4 input disks
# vxn-oci-runtime builds per container (up to the container rootfs size). A
# minimal Xen dom0 (~2GB extra) overflows on the first real image -- e.g. a
# node-based image is ~750MB, its ext4 input disk another ~800MB. Give dom0
# real headroom (~10GB) so users can load and run actual container images.
# Override VXN_DOM0_EXTRA_SPACE to size it for your images.
VXN_DOM0_EXTRA_SPACE ?= "10000000"
IMAGE_ROOTFS_EXTRA_SPACE:pn-xen-image-minimal = "${VXN_DOM0_EXTRA_SPACE}"
