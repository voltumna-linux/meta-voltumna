#!/bin/bash

YOCTO_BRANCH="scarthgap"
REPO_DIR="poky-amd-${YOCTO_BRANCH}"

# Clone poky repository
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.yoctoproject.org/poky" "${REPO_DIR}"

# Change to the poky directory
cd "${REPO_DIR}"

# Clone meta-openembedded and meta-dpdk repositories
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.openembedded.org/meta-openembedded"
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.yoctoproject.org/meta-dpdk"

# Clone meta-virtualization for enable virtualization or libvirt
git clone https://git.yoctoproject.org/meta-virtualization -b scarthgap

# Clone meta-secure-core for tpm tools
#git clone -b master https://github.com/Wind-River/meta-secure-core.git

# Clone meta-amd repository using SSH
git clone https://git.yoctoproject.org/meta-amd -b master
# Clone for tpm-tools
#git clone -b kirkstone https://github.com/Wind-River/meta-secure-core.git
git clone -b scarthgap  https://git.yoctoproject.org/git/meta-security

# Checkout specific tags and branches
git checkout --quiet tags/yocto-5.0
cd meta-openembedded
git checkout --quiet 4a7bb77f7ebe0ac8be5bab5103d8bd993e17e18d
cd ../meta-dpdk
git checkout --quiet 0f12d2eddf2f7cde8de274ffe225f3c8e912928d
