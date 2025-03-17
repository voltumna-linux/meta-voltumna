#!/bin/bash

YOCTO_BRANCH="kirkstone"
REPO_DIR="poky-amd-${YOCTO_BRANCH}"

# Clone poky repository
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.yoctoproject.org/poky" "${REPO_DIR}"

# Change to the poky directory
cd "${REPO_DIR}"

# Clone meta-openembedded and meta-dpdk repositories
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.openembedded.org/meta-openembedded"
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.yoctoproject.org/meta-dpdk"

# Clone meta-virtualization for enable virtualization or libvirt
git clone https://git.yoctoproject.org/meta-virtualization -b kirkstone

# Clone meta-secure-core for tpm tools
#git clone -b master https://github.com/Wind-River/meta-secure-core.git

# Clone meta-amd repository using SSH
git clone "ssh://gerritgit/eesc/ec/ese/meta-amd"
# Clone for tpm-tools
#git clone -b kirkstone https://github.com/Wind-River/meta-secure-core.git
git clone -b kirkstone https://git.yoctoproject.org/git/meta-security

# Checkout specific tags and branches
git checkout --quiet tags/yocto-4.0.9
cd meta-openembedded
git checkout --quiet 402affcc073db39f782c1ebfd718edd5f11eed4c
cd ../meta-dpdk
git checkout --quiet 12cd9701455f17ff86681dba86e5c10f7b0deb7c
cd ../meta-amd
git checkout kirkstone

