# Release archives are image types so do_image_complete deploys and caches them.
# do_image runs IMAGE_PREPROCESS_COMMAND before either archive task.
IMAGE_TYPES:append = " net.tar os.tar"

# OE-Core's dependency validator treats every dotted suffix as a conversion.
# Declare the suffix for that check only: do not add tar to CONVERSIONTYPES,
# since net.tar and os.tar are complete image types, not conversions.
CONVERSION_CMD:tar ?= ":"

VOLTUMNA_NETBOOT ?= ""
VOLTUMNA_TFTP_ROOT = "${WORKDIR}/release-netboot"

do_image_net_tar[depends] += "tar-replacement-native:do_populate_sysroot virtual/bootloader:do_deploy"
do_image_net_tar[cleandirs] += "${VOLTUMNA_TFTP_ROOT}"
do_image_os_tar[depends] += "tar-replacement-native:do_populate_sysroot"

voltumna_prepare_netboot() {
    case "${VOLTUMNA_NETBOOT}" in
        grub)
            for bootfile in grub-efi-bootx64.efi grub-bootx86.pxe; do
                if [ ! -f "${DEPLOY_DIR_IMAGE}/$bootfile" ]; then
                    continue
                fi
                case "$bootfile" in
                    grub-efi-bootx64.efi) bootdir=EFI/BOOT; bootname=bootx64.efi ;;
                    grub-bootx86.pxe) bootdir=BOOT; bootname=bootx86.pxe ;;
                esac
                mkdir -p "${VOLTUMNA_TFTP_ROOT}/tftpboot/$bootdir"
                install -m 644 "${DEPLOY_DIR_IMAGE}/$bootfile" \
                    "${VOLTUMNA_TFTP_ROOT}/tftpboot/$bootdir/$bootname"
                install -m 644 "${DEPLOY_DIR_IMAGE}/grub-${IMAGE_LINK_NAME}.cfg" \
                    "${VOLTUMNA_TFTP_ROOT}/tftpboot/$bootdir/grub.cfg"
                sed -i -e 's,default=localboot,default=netboot,g' \
                    "${VOLTUMNA_TFTP_ROOT}/tftpboot/$bootdir/grub.cfg"
            done
            ;;
        uboot)
            mkdir -p "${VOLTUMNA_TFTP_ROOT}/tftpboot"
            install -m 644 "${DEPLOY_DIR_IMAGE}/boot.scr.uimg" \
                "${VOLTUMNA_TFTP_ROOT}/tftpboot/boot.scr.uimg"
            install -m 644 "${DEPLOY_DIR_IMAGE}/uEnv-${IMAGE_LINK_NAME}.txt" \
                "${VOLTUMNA_TFTP_ROOT}/tftpboot/uEnv.txt"
            sed -i -e 's,\.osdir,voltumna,g' "${VOLTUMNA_TFTP_ROOT}/tftpboot/uEnv.txt"
            ;;
        "") ;;
        *) bbfatal "Unknown VOLTUMNA_NETBOOT: ${VOLTUMNA_NETBOOT}" ;;
    esac
}

IMAGE_CMD:net.tar() {
    voltumna_prepare_netboot
    rootfs=$(basename "${IMAGE_ROOTFS}")
    # WIC may hardlink files concurrently, changing ctime (tar exit status 1).
    tar --owner=0 --group=0 --numeric-owner \
        -cf "${IMGDEPLOYDIR}/${IMAGE_NAME}.net.tar" \
        -C "${IMAGE_ROOTFS}/.." --exclude='.osdir*' \
        --transform "s;^$rootfs;nfsroot;" "$rootfs" || [ $? -eq 1 ]
    if [ -d "${VOLTUMNA_TFTP_ROOT}/tftpboot" ]; then
        tar --owner=0 --group=0 --numeric-owner \
            -rf "${IMGDEPLOYDIR}/${IMAGE_NAME}.net.tar" \
            -C "${VOLTUMNA_TFTP_ROOT}" tftpboot
    fi
}

IMAGE_CMD:os.tar() {
    tar --owner=0 --group=0 --numeric-owner \
        -cf "${IMGDEPLOYDIR}/${IMAGE_NAME}.os.tar" \
        -C "${IMAGE_ROOTFS}/.osdir" "${IMAGE_NAME}" || [ $? -eq 1 ]
}
