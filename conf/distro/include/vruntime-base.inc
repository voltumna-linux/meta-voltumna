# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# Shared base for vruntime and vcontainer distros
#
# Provides the stripped-down DISTRO_FEATURES, opted-out features, and
# native class overrides common to all minimal container/VM builds.

# Base on oe-core's self-contained minimal distro skeleton rather than
# meta-poky's poky.conf. meta-virt ships multiple distros (vruntime,
# vcontainer) and should not drag in the poky *reference* distro -- that
# coupled these distros to meta-poky being in bblayers.conf and silently
# pulled poky policy (poky-sanity, poky-world-exclude, SANITY_TESTED_DISTROS,
# rpm, sysvinit) we never asked for. defaultsetup.conf lives in oe-core
# (always present) and provides default providers/distrovars, tcmode/tclibc,
# security_flags and init-manager -- everything a functional distro needs.
require conf/distro/defaultsetup.conf

# poky.conf pinned these; defaultsetup.conf leaves them to oe-core defaults.
# Keep rpm packaging (unchanged from the poky-based behavior) and pin the
# kernel so dropping poky.conf does not let linux-yocto float. INIT_MANAGER
# is deliberately NOT pinned here -- defaultsetup.conf defaults to systemd,
# which is what this layer uses (the VM rootfs overrides to busybox in
# vruntime.conf; nothing in the layer relies on sysvinit).
PACKAGE_CLASSES ?= "package_rpm"
PREFERRED_VERSION_linux-yocto ?= "7.2%"
PREFERRED_VERSION_linux-yocto-rt ?= "7.2%"

# Minimal distro features for container runtime environment
# - acl: Access control lists (containers need this)
# - ext2: Filesystem support
# - ipv4/ipv6: Network support for container networking
# - seccomp: Security for container isolation
# - vfat: For potential boot partition support
# - pci: PCI device support (virtio devices)
# - vcontainer: Enable vdkr/vpdmn kernel config fragments (9p, squashfs, overlayfs)
# - vxn: Xen container integration
#
# Explicitly NOT included: x11, wayland, pulseaudio, bluetooth, wifi, nfc, 3g, pcmcia
# 'virtualization' is required for the container kernel fragment (container.scc ->
# 9p/squashfs/overlayfs, container-net.cfg, vxn.cfg), which linux-%.bbappend gates
# on it. Declare it here so vruntime is self-contained and does not depend on a
# top-level DISTRO_FEATURES:append (e.g. meta-virt-host.conf) leaking through the
# multiconfig. It pulls no userspace packages -- only the kernel config the VM
# needs -- so it does not bloat the rootfs.
DISTRO_FEATURES = "acl ext2 ipv4 ipv6 seccomp vfat pci vcontainer vxn virtualization"

# Opt out of default distro features not needed by container runtime
# environments. Without this, gobject-introspection-data enables
# python3-pygobject (which DEPENDS on cairo), and wayland enables
# pygobject's cairo PACKAGECONFIG -- both are masked in vruntime builds.
# Note: OE-core replaced DISTRO_FEATURES_BACKFILL_CONSIDERED with
# DISTRO_FEATURES_OPTED_OUT (commit 159148f4de2).
DISTRO_FEATURES_OPTED_OUT = "pulseaudio gobject-introspection-data opengl ptest multiarch wayland vulkan"

# Native and nativesdk classes: keep the stripped feature set out of the
# build tools. Empty here matches the previous poky-based behavior
# (POKY_DEFAULT_DISTRO_FEATURES was "") without referencing a poky symbol.
DISTRO_FEATURES:class-native = ""
DISTRO_FEATURES:class-nativesdk = ""

# Keep images small - no documentation or debug
EXTRA_IMAGE_FEATURES = ""
