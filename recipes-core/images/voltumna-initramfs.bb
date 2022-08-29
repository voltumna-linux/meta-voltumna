DESCRIPTION = "Small image capable of mounting all parts of the final system."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/files/common-licenses/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI += "file://init"

PV = "1.0"

# Avoid (R)DEPENDS which add other dependencies
PACKAGE_INSTALL = "busybox busybox-udhcpc e2fsprogs-e2fsck udev"

# Use dynamic /dev population
USE_DEVFS = "1"

# Use a specific name for include this into kernel
export IMAGE_BASENAME = "voltumna-initramfs"
IMAGE_NAME = "${IMAGE_BASENAME}-${MACHINE}-${PV}"

# Do not pollute the initrd image with rootfs features
IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"
LDCONFIGDEPEND = ""

install() {
	cp ${FILE_DIRNAME}/files/init ${IMAGE_ROOTFS}
	chmod 744 ${IMAGE_ROOTFS}/init

	mkdir -p ${IMAGE_ROOTFS}/dev ${IMAGE_ROOTFS}/proc \
		${IMAGE_ROOTFS}/sys ${IMAGE_ROOTFS}/mnt/rootfs 

	mknod -m 622 ${IMAGE_ROOTFS}/dev/console c 5 1
	mknod -m 666 ${IMAGE_ROOTFS}/dev/null c 1 3
	mknod -m 666 ${IMAGE_ROOTFS}/dev/zero c 1 5
}

remove_var() {
	rm -fr ${IMAGE_ROOTFS}${localstatedir}
}

IMAGE_PREPROCESS_COMMAND_append += " remove_var;"

BAD_RECOMMENDATIONS += "busybox-syslog"
inherit image
