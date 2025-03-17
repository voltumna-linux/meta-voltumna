# 1. Setting up the build system

Building images for AMD machines requires setting up the Yocto Project
Build System. Please follow the guidelines on
[Yocto Project Overview and Concepts Manual](https://docs.yoctoproject.org/4.0.5/overview-manual/index.html)
and [Yocto Project Quick Build Guide](https://docs.yoctoproject.org/4.0.5/brief-yoctoprojectqs/index.html)
if you are not familiar with the Yocto Project and it's Build System.

Running the following commands will setup the build system and will
enable us to build recipes & images for any of the supported AMD machines.

### 1.1 Prerequisites

Install the build system's dependencies:
```sh
sudo apt install -y gawk wget git diffstat unzip texinfo gcc \
     build-essential chrpath socat cpio python3 python3-pip \
     python3-pexpect xz-utils debianutils iputils-ping python3-git \
     python3-jinja2 libegl1-mesa libsdl1.2-dev pylint3 xterm \
     python3-subunit mesa-common-dev
```

### 1.2 Download the build system and the meta-data layers

Select the Yocto Project branch:
```sh
YOCTO_BRANCH="scarthgap"
REPO_DIR="poky-amd-${YOCTO_BRANCH}"
```

Clone the git repositories: 
```sh
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.yoctoproject.org/poky" "${REPO_DIR}"
cd "${REPO_DIR}"
# Clone meta-openembedded and meta-dpdk repositories
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.openembedded.org/meta-openembedded"
git clone --single-branch --branch "${YOCTO_BRANCH}" "git://git.yoctoproject.org/meta-dpdk"

# Clone meta-virtualization for enable virtualization or libvirt
git clone https://git.yoctoproject.org/meta-virtualization -b scarthgap

# Clone meta-amd repository using SSH
git clone https://git.yoctoproject.org/meta-amd -b master

# Clone for tpm-tools
git clone -b scarthgap https://git.yoctoproject.org/git/meta-security
```

# Checkout specific tags and branches
```sh
git checkout --quiet tags/yocto-5.0
cd meta-openembedded
git checkout --quiet 4a7bb77f7ebe0ac8be5bab5103d8bd993e17e18d
cd ../meta-dpdk
git checkout --quiet 0f12d2eddf2f7cde8de274ffe225f3c8e912928d

```
---
#### What's next

Continue to "Section 2 - Setting up and starting a build"
([BUILD.md](BUILD.md)) for instructions on how to setup and start a
build for a particular AMD machine.
