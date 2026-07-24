# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# Shared base for vruntime and vcontainer distros
#
# Provides the stripped-down DISTRO_FEATURES, opted-out features, and
# native class overrides common to all minimal container/VM builds.

require conf/distro/poky.conf

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
DISTRO_FEATURES = "acl ext2 ipv4 ipv6 seccomp vfat pci vcontainer vxn"

# Opt out of default distro features not needed by container runtime
# environments. Without this, gobject-introspection-data enables
# python3-pygobject (which DEPENDS on cairo), and wayland enables
# pygobject's cairo PACKAGECONFIG -- both are masked in vruntime builds.
# Note: OE-core replaced DISTRO_FEATURES_BACKFILL_CONSIDERED with
# DISTRO_FEATURES_OPTED_OUT (commit 159148f4de2).
DISTRO_FEATURES_OPTED_OUT = "pulseaudio gobject-introspection-data opengl ptest multiarch wayland vulkan"

# Native and nativesdk classes need full features for build tools
DISTRO_FEATURES:class-native = "${POKY_DEFAULT_DISTRO_FEATURES}"
DISTRO_FEATURES:class-nativesdk = "${POKY_DEFAULT_DISTRO_FEATURES}"

# Keep images small - no documentation or debug
EXTRA_IMAGE_FEATURES = ""
