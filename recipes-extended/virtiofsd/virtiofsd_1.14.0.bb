SUMMARY = "virtio-fs vhost-user daemon"
DESCRIPTION = "A daemon that allows sharing of folders with a VM via virtio-fs"
HOMEPAGE = "https://gitlab.com/virtio-fs/virtiofsd"
LICENSE = "Apache-2.0 OR BSD-3-Clause"
LIC_FILES_CHKSUM = " \
    file://LICENSE-APACHE;md5=3b83ef96387f14655fc854ddc3c6bd57 \
    file://LICENSE-BSD-3-Clause;md5=b1ed361f9fc790c1054d81a7ef041a34 \
"

DEPENDS = "libseccomp libcap-ng"

inherit features_check
REQUIRED_DISTRO_FEATURES = "seccomp"

SRC_URI += "crate://crates.io/virtiofsd/1.14.0"
SRC_URI[virtiofsd-1.14.0.sha256sum] = "7051accc9cf2816e25945c8216e6d4be2b4e75fc5e77559cd7eed5e400245cc1"

inherit cargo
inherit cargo-update-recipe-crates

include virtiofsd-crates.inc
