# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# BBMASK for oe-core (meta) layer in vruntime multiconfig builds.
#
# Masks entire recipe categories with zero recipes in the vruntime
# dependency graph (verified via bitbake -g and PN-level cross-check).
#
# KEPT: recipes-bsp, recipes-connectivity, recipes-core, recipes-devtools,
#       recipes-extended, recipes-gnome, recipes-kernel, recipes-support

# ---------------------------------------------------------------------------
# Graphics - mask only subdirs with zero needed recipes (39 of 49 subdirs)
# Keep: wayland, libsdl2, virglrenderer, libepoxy, drm, mesa, spir,
#       xorg-lib, xorg-proto, xorg-app, xorg-util (qemu-system-native deps)
# ---------------------------------------------------------------------------
BBMASK += "/meta/recipes-graphics/(?!wayland|libsdl2|virglrenderer|libepoxy|drm|mesa|spir|xorg-lib|xorg-proto|xorg-app|xorg-util)"

# ---------------------------------------------------------------------------
# Multimedia - mask all except alsa/ and libpng/ (qemu-system-native deps)
# ---------------------------------------------------------------------------
BBMASK += "/meta/recipes-multimedia/(?!alsa|libpng)"

# ---------------------------------------------------------------------------
# Sato desktop (~25 recipes) - Matchbox, webkit, desktop UI
# ---------------------------------------------------------------------------
BBMASK += "/meta/recipes-sato/"

# ---------------------------------------------------------------------------
# RT kernel (~4 recipes) - Real-time kernel, not needed for containers
# ---------------------------------------------------------------------------
BBMASK += "/meta/recipes-rt/"

# ---------------------------------------------------------------------------
# Orphaned bbappends in other layers (base recipes masked above)
# ---------------------------------------------------------------------------
# meta-yocto-bsp bbappend for masked oe-core graphics
BBMASK += "meta-yocto-bsp/recipes-graphics/xorg-xserver/xserver-xf86-config"
# meta-erlang bbappend for oe-core mesa (mesa is kept, but libglu not needed)
BBMASK += "meta-erlang/recipes-graphics/mesa/libglu"
