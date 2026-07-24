# SPDX-FileCopyrightText: Copyright (C) 2025 Bruce Ashfield
#
# SPDX-License-Identifier: MIT
#
# BBMASK for meta-virtualization layer in vruntime multiconfig builds.
#
# Masks recipes not needed by vdkr (docker) or vpdmn (podman) container
# runtime images. Only affects vruntime multiconfig parsing; main build
# is unaffected.
#
# Generated from bitbake -g dependency graph analysis.
#
# KEPT (.bb recipes): aardvark-dns, catatonit, conmon, containerd,
#   container-host-config, crun, docker-moby, netavark, podman, runc,
#   skopeo, tini, vcontainer/*, cni, slirp4netns
# KEPT (bbappends only): busybox, initscripts, libxcrypt, sysvinit,
#   go-md2man, qemu, yajl, iptables, libseccomp, linux/linux-yocto, bind

# ---------------------------------------------------------------------------
# Virtualization platforms (not containers)
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
# Infrastructure / monitoring
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-extended/ceph/"
BBMASK += "meta-virtualization/recipes-extended/cloud-init/"
BBMASK += "meta-virtualization/recipes-extended/cockpit-machines/"
BBMASK += "meta-virtualization/recipes-extended/nagios/"
BBMASK += "meta-virtualization/recipes-extended/oath/"
BBMASK += "meta-virtualization/recipes-extended/irqbalance/"

# ---------------------------------------------------------------------------
# Container images / bundles / cross-deploy (main build only)
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-extended/images/"
BBMASK += "meta-virtualization/recipes-extended/container-bundles/"
BBMASK += "meta-virtualization/recipes-extended/container-cross-deploy/"

# ---------------------------------------------------------------------------
# Not in dependency graph (rootless/overlay helpers not RDEPENDS)
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-extended/fuse-overlayfs/"
BBMASK += "meta-virtualization/recipes-extended/rootlesskit/"

# ---------------------------------------------------------------------------
# Container orchestration / tools not in vruntime
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
BBMASK += "meta-virtualization/recipes-containers/docker-distribution/"

# ---------------------------------------------------------------------------
# Container tooling not used by vdkr/vpdmn
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-containers/cgroup-lite/"
BBMASK += "meta-virtualization/recipes-containers/riddler/"
BBMASK += "meta-virtualization/recipes-containers/umoci/"
BBMASK += "meta-virtualization/recipes-containers/sloci-image/"
BBMASK += "meta-virtualization/recipes-containers/oci-image-tools/"
BBMASK += "meta-virtualization/recipes-containers/oci-runtime-spec/"
BBMASK += "meta-virtualization/recipes-containers/oci-runtime-tools/"
BBMASK += "meta-virtualization/recipes-containers/oci-systemd-hook/"
BBMASK += "meta-virtualization/recipes-containers/oci-image-spec/"
BBMASK += "meta-virtualization/recipes-containers/oci-base-images/"
BBMASK += "meta-virtualization/recipes-containers/container-registry/"
BBMASK += "meta-virtualization/recipes-containers/go-digest/"
BBMASK += "meta-virtualization/recipes-containers/go-errors/"
BBMASK += "meta-virtualization/recipes-containers/go-spf13-cobra/"
BBMASK += "meta-virtualization/recipes-containers/go-spf13-pflag/"

# ---------------------------------------------------------------------------
# Other categories not needed
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-demo/"
BBMASK += "meta-virtualization/recipes-graphics/"
BBMASK += "meta-virtualization/recipes-core/kata-containers/"
BBMASK += "meta-virtualization/recipes-core/runx/"
BBMASK += "meta-virtualization/recipes-networking/openvswitch/"
BBMASK += "meta-virtualization/recipes-networking/netns/"
BBMASK += "meta-virtualization/recipes-networking/passt/"

# ---------------------------------------------------------------------------
# Dev recipes not needed (keep qemu & yajl bbappends, keep linux bbappends)
# ---------------------------------------------------------------------------
BBMASK += "meta-virtualization/recipes-devtools/python/"
BBMASK += "meta-virtualization/recipes-devtools/go-dirhash-native/"
BBMASK += "meta-virtualization/recipes-devtools/yq/"
BBMASK += "meta-virtualization/recipes-kernel/lopper/"

# Individual go libraries not needed by vruntime builds
BBMASK += "meta-virtualization/recipes-devtools/go/go-connections"
BBMASK += "meta-virtualization/recipes-devtools/go/go-capability"
BBMASK += "meta-virtualization/recipes-devtools/go/go-build"
BBMASK += "meta-virtualization/recipes-devtools/go/compose-file"
BBMASK += "meta-virtualization/recipes-devtools/go/go-cli"
BBMASK += "meta-virtualization/recipes-devtools/go/go-context"
BBMASK += "meta-virtualization/recipes-devtools/go/go-logrus"
BBMASK += "meta-virtualization/recipes-devtools/go/go-libtrust"
BBMASK += "meta-virtualization/recipes-devtools/go/go-patricia"
BBMASK += "meta-virtualization/recipes-devtools/go/go-systemd"
BBMASK += "meta-virtualization/recipes-devtools/go/go-pty"
BBMASK += "meta-virtualization/recipes-devtools/go/go-dbus"
BBMASK += "meta-virtualization/recipes-devtools/go/go-distribution"
BBMASK += "meta-virtualization/recipes-devtools/go/go-metalinter"
BBMASK += "meta-virtualization/recipes-devtools/go/go-mux"
BBMASK += "meta-virtualization/recipes-devtools/go/grpc-go"
BBMASK += "meta-virtualization/recipes-devtools/go/go-fsnotify"
# go-md2man KEPT (crun, conmon DEPENDS on go-md2man-native)

# ---------------------------------------------------------------------------
# Orphaned bbappends in other layers (base recipes masked above)
# ---------------------------------------------------------------------------
BBMASK += "meta-openstack/recipes-extended/libvirt/"
