SUMMARY = "A minimal image containing crosvm to demo its usage."

KVM_MODULES = ""

# kvm is built-in on arm64
KVM_MODULES:aarch64 = ""

KVM_MODULES:x86-64 = " \
    kernel-module-kvm \
    kernel-module-kvm-intel \
    kernel-module-kvm-amd \
"

IMAGE_INSTALL = "packagegroup-core-boot crosvm"
IMAGE_INSTALL:append = " ${KVM_MODULES}"

IMAGE_LINGUAS = " "

LICENSE = "MIT"

inherit core-image

# Guest artifact source settings.
# This is intentionally a normal variable
# assignment so it can be overridden in local.conf. The do_rootfs[depends]
# is added at parse time, so any local.conf override is picked up correctly.
CROSVM_GUEST_IMAGE_RECIPE ?= "core-image-minimal"
CROSVM_GUEST_IMAGE_FSTYPE ?= "ext4"
CROSVM_GUEST_ROOTFS ?= "${CROSVM_GUEST_IMAGE_RECIPE}-${MACHINE}.rootfs.${CROSVM_GUEST_IMAGE_FSTYPE}"
CROSVM_GUEST_KERNEL ?= "${KERNEL_IMAGETYPE}"

# Final location inside the host/root image.
CROSVM_GUEST_TARGET_DIR ?= "/var/lib/crosvm/images"
CROSVM_GUEST_TARGET_ROOTFS_NAME ?= "guest.${CROSVM_GUEST_IMAGE_FSTYPE}"
CROSVM_GUEST_TARGET_KERNEL_NAME ?= "guest-kernel"

# Ensure guest image and kernel are available before rootfs postprocess runs.
# The image also depends on guest rootfs to avoid stale consumption
# of deployed guest image artifact.
# The same kernel is used for both the host and guest.
do_rootfs[depends] += "\
	${CROSVM_GUEST_IMAGE_RECIPE}:do_image_complete \
	${CROSVM_GUEST_IMAGE_RECIPE}:do_rootfs \
	virtual/kernel:do_deploy \
"

# Copy guest rootfs+kernel into the host rootfs for crosvm demo runtime.
bundle_crosvm_guest() {
    set -e

    local deploy_dir="${DEPLOY_DIR_IMAGE}"
    local rootfs_src="${deploy_dir}/${CROSVM_GUEST_ROOTFS}"
    local kernel_src="${deploy_dir}/${CROSVM_GUEST_KERNEL}"
    local target_dir="${IMAGE_ROOTFS}${CROSVM_GUEST_TARGET_DIR}"

    if [ ! -e "$rootfs_src" ]; then
        bbfatal "Cannot find guest rootfs. Tried: \
                ${deploy_dir}/${CROSVM_GUEST_ROOTFS} and \
                ${deploy_dir}/${CROSVM_GUEST_IMAGE_RECIPE}-${MACHINE}.rootfs.${CROSVM_GUEST_IMAGE_FSTYPE}"
    fi

    if [ ! -e "$kernel_src" ]; then
        bbfatal "Cannot find guest kernel. Tried: \
                ${deploy_dir}/${CROSVM_GUEST_KERNEL}"
    fi

    install -d "$target_dir"

    install -m 0644 "$(readlink -f "$rootfs_src")" \
                    "$target_dir/${CROSVM_GUEST_TARGET_ROOTFS_NAME}"

    install -m 0644 "$(readlink -f "$kernel_src")" \
                    "$target_dir/${CROSVM_GUEST_TARGET_KERNEL_NAME}"
}

ROOTFS_POSTPROCESS_COMMAND += "bundle_crosvm_guest;"

IMAGE_ROOTFS_SIZE = "0"

KERNEL_MODULE_AUTOLOAD:append:x86-64 = " kvm kvm_amd kvm_intel"
