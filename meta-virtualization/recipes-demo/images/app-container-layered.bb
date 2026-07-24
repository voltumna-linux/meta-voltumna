SUMMARY = "Layered Application container - test OCI_BASE_IMAGE"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"

# Use container-base as the base layer
OCI_BASE_IMAGE = "container-base"

# Use CMD so `docker run image /bin/sh` works as expected
OCI_IMAGE_CMD = "/bin/sh -c 'echo Hello from layered container'"

IMAGE_FSTYPES = "container oci"
inherit image
inherit image-oci

IMAGE_FEATURES = ""
IMAGE_LINGUAS = ""
NO_RECOMMENDATIONS = "1"

# Only add packages not in base - this is the "app layer"
IMAGE_INSTALL = " \
       base-files \
       base-passwd \
       netbase \
       busybox \
       curl \
"

# Allow build with or without a specific kernel
IMAGE_CONTAINER_NO_DUMMY = "1"

# Workaround /var/volatile for now
ROOTFS_POSTPROCESS_COMMAND += "rootfs_fixup_var_volatile ; "
rootfs_fixup_var_volatile () {
    install -m 1777 -d ${IMAGE_ROOTFS}/${localstatedir}/volatile/tmp
    install -m 755 -d ${IMAGE_ROOTFS}/${localstatedir}/volatile/log
}
