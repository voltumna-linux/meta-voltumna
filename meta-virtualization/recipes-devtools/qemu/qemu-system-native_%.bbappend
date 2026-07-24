# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# Enable virtfs (virtio-9p) for vcontainer cross-architecture container bundling.
# This is required for the fast batch-import path in container-cross-install.
#
# Note: Native recipes don't see target DISTRO_FEATURES directly.
# The layer.conf propagates virtualization and vcontainer to DISTRO_FEATURES
# using DISTRO_FEATURES_FILTER_NATIVE.

PACKAGECONFIG:append = "${@bb.utils.contains_any('DISTRO_FEATURES', 'virtualization vcontainer', ' virtfs', '', d)}"
