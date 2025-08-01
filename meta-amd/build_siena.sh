#!/bin/bash
YOCTO_BRANCH="scarthgap"
MACHINE='siena'
source ./oe-init-build-env build-${MACHINE}-${YOCTO_BRANCH}

tee conf/auto.conf <<EOF
DL_DIR ?= "\${TOPDIR}/../downloads"
SSTATE_DIR ?= "\${TOPDIR}/../sstate-cache"
MACHINE = "${MACHINE}"
DISTRO = "poky-amd"
EOF

bitbake-layers add-layer ../meta-openembedded/meta-oe
bitbake-layers add-layer ../meta-openembedded/meta-python
bitbake-layers add-layer ../meta-openembedded/meta-networking
bitbake-layers add-layer ../meta-dpdk
bitbake-layers add-layer ../meta-amd/meta-amd-distro
bitbake-layers add-layer ../meta-amd/meta-amd-bsp
bitbake-layers add-layer ../meta-openembedded/meta-filesystems
bitbake-layers add-layer ../meta-virtualization
bitbake-layers add-layer ../meta-security/meta-tpm/
bitbake core-image-sato -k
