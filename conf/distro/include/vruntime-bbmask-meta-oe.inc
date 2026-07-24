# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# BBMASK for meta-openembedded sublayers in vruntime multiconfig builds.
#
# Masks recipe categories with zero recipes in the vruntime dependency
# graph (verified via bitbake -g).
#
# KEPT from meta-oe:
#   recipes-devtools (abseil-cpp, jsoncpp, protobuf, yajl)
#   recipes-extended (jansson)
#   recipes-support (lvm2)
# KEPT from meta-networking:
#   recipes-filter (nftables, libnftnl)
#   recipes-support (bridge-utils)
# KEPT from meta-filesystems: NONE (entire layer masked)
# KEPT from meta-python: NONE (entire layer masked)
# KEPT from meta-webserver: NONE (entire layer masked)

# ---------------------------------------------------------------------------
# meta-oe: mask all categories except devtools, extended, support
# Uses negative lookahead to keep the three needed categories
# ---------------------------------------------------------------------------
BBMASK += "meta-oe/recipes-(?!devtools|extended|support)"

# ---------------------------------------------------------------------------
# meta-networking: mask all categories except filter, support
# ---------------------------------------------------------------------------
BBMASK += "meta-networking/recipes-(?!filter|support)"

# ---------------------------------------------------------------------------
# Entire layers with 0 recipes in the dependency graph.
# Clear BBFILE_COLLECTIONS entries for fully-masked layers so BitBake
# does not warn about zero files matching BBFILE_PATTERN.
# The layers remain in bblayers.conf (shared with main build) but
# contribute no recipes to vruntime/vcontainer multiconfigs.
# ---------------------------------------------------------------------------
BBMASK += "meta-filesystems/"
BBMASK += "meta-python/"
BBMASK += "meta-webserver/"
# Warning suppression for these fully-masked layers is in meta-virt-host.conf
# (BBFILE_PATTERN_IGNORE_EMPTY) because BitBake checks the base datastore,
# not per-multiconfig datastores.

# ---------------------------------------------------------------------------
# Orphaned bbappends in other layers (base recipes masked above)
# ---------------------------------------------------------------------------
# meta-openstack bbappend for meta-oe postgresql (recipes-dbs masked)
BBMASK += "meta-openstack/recipes-dbs/postgresql/"
# meta-oe dynamic-layers bbappend for meta-networking packagegroup (recipes-core masked)
BBMASK += "meta-oe/dynamic-layers/networking-layer/recipes-core/"
