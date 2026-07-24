# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# BBMASK for vcontainer OCI image builder multiconfig builds.
#
# Lighter than vruntime's BBMASK: masks recipes irrelevant to container
# image construction (virtualization platforms, graphics, multimedia,
# desktop, orchestration) but keeps OCI tooling (umoci, skopeo),
# container image recipes, and the full container stack available.
#
# The vruntime BBMASK cannot be reused directly because it masks umoci,
# container-registry, recipes-extended/images/, and other recipes needed
# for OCI image building. BitBake BBMASK is append-only (no removal),
# so a separate lighter mask is required.

# ---------------------------------------------------------------------------
# oe-core: same masks as vruntime (graphics, multimedia, sato, rt)
# These are irrelevant to container image building.
# ---------------------------------------------------------------------------
BBMASK += "/meta/recipes-graphics/(?!wayland|libsdl2|virglrenderer|libepoxy|drm|mesa|spir|xorg-lib|xorg-proto|xorg-app|xorg-util)"
BBMASK += "/meta/recipes-multimedia/(?!alsa|libpng)"
BBMASK += "/meta/recipes-sato/"
BBMASK += "/meta/recipes-rt/"
BBMASK += "meta-yocto-bsp/recipes-graphics/xorg-xserver/xserver-xf86-config"
BBMASK += "meta-erlang/recipes-graphics/mesa/libglu"

# ---------------------------------------------------------------------------
# meta-virtualization: virtualization platforms (not containers)
# Same as vruntime — Xen, libvirt, etc. are irrelevant for OCI images.
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-extended/xen/"
BBMASK += "meta-virtualization/recipes-extended/xvisor/"
BBMASK += "meta-virtualization/recipes-extended/kvmtool/"
BBMASK += "meta-virtualization/recipes-extended/libvirt/"
BBMASK += "meta-virtualization/recipes-extended/libvmi/"
BBMASK += "meta-virtualization/recipes-extended/virt-manager/"
BBMASK += "meta-virtualization/recipes-extended/virt-viewer/"
BBMASK += "meta-virtualization/recipes-extended/virt-what/"
BBMASK += "meta-virtualization/recipes-extended/vhost-device/"
BBMASK += "meta-virtualization/recipes-extended/dev86/"
BBMASK += "meta-virtualization/recipes-extended/seabios/"
BBMASK += "meta-virtualization/recipes-extended/vgabios/"
BBMASK += "meta-virtualization/recipes-extended/upx/"
BBMASK += "meta-virtualization/recipes-extended/uxen/"
BBMASK += "meta-virtualization/recipes-extended/ipxe/"
BBMASK += "meta-virtualization/recipes-extended/diod/"
BBMASK += "meta-virtualization/recipes-extended/virtiofsd/"

# ---------------------------------------------------------------------------
# meta-virtualization: infrastructure / monitoring
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-extended/ceph/"
BBMASK += "meta-virtualization/recipes-extended/cloud-init/"
BBMASK += "meta-virtualization/recipes-extended/cockpit-machines/"
BBMASK += "meta-virtualization/recipes-extended/nagios/"
BBMASK += "meta-virtualization/recipes-extended/oath/"
BBMASK += "meta-virtualization/recipes-extended/irqbalance/"

# ---------------------------------------------------------------------------
# meta-virtualization: container orchestration / tools not needed for images
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-containers/kubernetes/"
BBMASK += "meta-virtualization/recipes-containers/k3s/"
BBMASK += "meta-virtualization/recipes-containers/cri-o/"
BBMASK += "meta-virtualization/recipes-containers/cri-tools/"
BBMASK += "meta-virtualization/recipes-containers/docker-compose/"
BBMASK += "meta-virtualization/recipes-containers/podman-compose/"
BBMASK += "meta-virtualization/recipes-containers/podman-tui/"
BBMASK += "meta-virtualization/recipes-containers/nerdctl/"
BBMASK += "meta-virtualization/recipes-containers/buildah/"
BBMASK += "meta-virtualization/recipes-containers/singularity/"
BBMASK += "meta-virtualization/recipes-containers/lxc/"
BBMASK += "meta-virtualization/recipes-containers/lxcfs/"
BBMASK += "meta-virtualization/recipes-containers/criu/"

# ---------------------------------------------------------------------------
# meta-virtualization: other categories not needed for container images
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-demo/"
BBMASK += "meta-virtualization/recipes-graphics/"
BBMASK += "meta-virtualization/recipes-core/kata-containers/"
BBMASK += "meta-virtualization/recipes-core/runx/"
BBMASK += "meta-virtualization/recipes-networking/openvswitch/"
BBMASK += "meta-virtualization/recipes-networking/netns/"
BBMASK += "meta-virtualization/recipes-networking/passt/"

# ---------------------------------------------------------------------------
# meta-oe / meta-networking: mask heavyweight categories
# ---------------------------------------------------------------------------
BBMASK += "meta-oe/recipes-(?!devtools|extended|support)"
BBMASK += "meta-networking/recipes-(?!filter|support)"
BBMASK += "meta-openstack/recipes-dbs/postgresql/"
BBMASK += "meta-oe/dynamic-layers/networking-layer/recipes-core/"
BBMASK += "meta-openstack/recipes-extended/libvirt/"

# ---------------------------------------------------------------------------
# Entire layers with 0 recipes in the container image dependency graph.
# Clear BBFILE_COLLECTIONS entries for fully-masked layers so BitBake
# does not warn about zero files matching BBFILE_PATTERN.
# ---------------------------------------------------------------------------
BBMASK += "meta-filesystems/"
BBMASK += "meta-python/"
BBMASK += "meta-webserver/"
# Warning suppression for these fully-masked layers is in meta-virt-host.conf
# (BBFILE_PATTERN_IGNORE_EMPTY) because BitBake checks the base datastore,
# not per-multiconfig datastores.

# ---------------------------------------------------------------------------
# NOT MASKED (differs from vruntime):
#   recipes-extended/images/          - container image recipes
#   recipes-containers/umoci/         - OCI image manipulation
#   recipes-containers/container-registry/ - registry push
#   recipes-containers/oci-image-tools/    - OCI tooling
#   recipes-containers/oci-image-spec/     - OCI spec
#   recipes-containers/sloci-image/        - simple OCI image builder
#   recipes-containers/oci-base-images/    - external base images
#   recipes-extended/container-bundles/    - container bundling
#   recipes-extended/container-cross-deploy/ - cross-install
#   recipes-extended/fuse-overlayfs/       - overlay support
#   recipes-extended/rootlesskit/          - rootless containers
# ---------------------------------------------------------------------------
