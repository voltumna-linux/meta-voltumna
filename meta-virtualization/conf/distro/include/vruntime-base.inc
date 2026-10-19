# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# Shared base for vruntime and vcontainer distros
#
# Provides the stripped-down DISTRO_FEATURES, opted-out features, and
# native class overrides common to all minimal container/VM builds.

# These are their own distros (vruntime, vcontainer), deliberately NOT based
# on meta-poky's poky.conf: that dragged in the poky *reference* distro policy
# (poky-sanity, poky-world-exclude, SANITY_TESTED_DISTROS, rpm, sysvinit) and
# coupled us to meta-poky being in bblayers.conf. Like poky.conf and every
# other oe-core distro, this file sets only the distro's own features and
# overrides; the base skeleton (default providers/distrovars, tcmode/tclibc,
# security_flags, init-manager) is supplied by bitbake.conf, which includes
# conf/distro/defaultsetup.conf immediately after conf/distro/${DISTRO}.conf
# for every distro. Do NOT "require defaultsetup.conf" here -- doing so parses
# it twice and triggers "Duplicate inclusion" warnings (Yocto bug 16451).
#
# Because the distro conf is parsed before defaultsetup, these ?= pins win
# over defaultsetup's own ?= defaults: keep rpm packaging and pin the kernel
# so we do not inherit ipk / let linux-yocto float. INIT_MANAGER is left to
# defaultsetup's systemd default, which matches the layer (the VM rootfs
# overrides to busybox init in vruntime.conf; nothing relies on sysvinit).
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
