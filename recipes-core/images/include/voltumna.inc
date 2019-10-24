IMAGE_LINGUAS = "en-us"
IMAGE_BOOT_FILES_remove = "${KERNEL_IMAGETYPE} ${KERNEL_DEVICETREE}"

EXTRA_IMAGE_FEATURES = "ssh-server-openssh"

WIC_CREATE_EXTRA_ARGS += " --no-fstab-update"

DEPENDS += "voltumna-initramfs"
DEPENDS_append_x86-64 += "syslinux"

IMAGE_CLASSES += "extrausers"
EXTRA_USERS_PARAMS = "\
    usermod -aG shadow www; \
"

IMAGE_INSTALL_append += "kernel-image kernel-devicetree ${MACHINE_EXTRA_RRECOMMENDS} \
	bash bash-completion coreutils util-linux util-linux-sfdisk glibc-utils less \
	procps psmisc tzdata tzdata-europe polkit socat stress-ng sed tar xz grep \
	findutils file nano debianutils 96boards-tools dosfstools nfs-utils-client \
	openssh-sftp-server os-update inetutils-ping inetutils-telnet net-tools"

copy_etc_into_factory() {
	# Use systemd's nsswitch.conf file instead of the base-files's one
	mv ${IMAGE_ROOTFS}${datadir}/factory/etc/nsswitch.conf ${IMAGE_ROOTFS}${sysconfdir}

	# Copy files in factory/etc e create entries accordingly
	#cp -r ${IMAGE_ROOTFS}${sysconfdir} ${IMAGE_ROOTFS}${datadir}/factory/
}

use_initramfs_bundled_kernel() {
	rm -f ${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE}-*
	cp -r ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-initramfs-${MACHINE}-* \
		${IMAGE_ROOTFS}/usr/boot
	rm -f ${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE} 
	lnr ${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE}-initramfs-${MACHINE}-* \
		${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE} 
}

compute_sum() {
	MD5SUM=$(cd ${IMAGE_ROOTFS}/usr && find -type f -exec md5sum {} \;)
	echo "$MD5SUM" >> ${IMAGE_ROOTFS}/usr/.MD5SUM.txt
}

# This must be the latest!
move_usr_into_osdir() {
	mkdir ${IMAGE_ROOTFS}/.osdir
	mv ${IMAGE_ROOTFS}/usr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}
	mkdir ${IMAGE_ROOTFS}/usr
	rm -f ${IMAGE_ROOTFS}/.osdir/factory ${IMAGE_ROOTFS}/.osdir/default
	lnr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}/ ${IMAGE_ROOTFS}/.osdir/factory
	lnr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}/ ${IMAGE_ROOTFS}/.osdir/default
}

IMAGE_PREPROCESS_COMMAND_append += " use_initramfs_bundled_kernel; copy_etc_into_factory; compute_sum; move_usr_into_osdir;"

BAD_RECOMMENDATIONS += "busybox-syslog grub-common"
inherit core-image

IMAGE_CMD_tar() {
	${IMAGE_CMD_TAR} --numeric-owner --exclude='.osdir*' -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar --transform "s;^rootfs;nfsroot;" -C ${IMAGE_ROOTFS}/.. rootfs || [ $? -eq 1 ]
	${IMAGE_CMD_TAR} --numeric-owner -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.os.tar  -C ${IMAGE_ROOTFS}/.osdir ${IMAGE_NAME} || [ $? -eq 1 ]
}

IMAGE_CMD_tar_append_arm() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/boot.scr.uimg ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.uEnv.txt ${TEMPORARYDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir/,,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}

IMAGE_CMD_tar_append_x86-64() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot/EFI/BOOT
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${TEMPORARYDIR}/tftpboot/EFI/BOOT/bootx64.efi
	install -m 644 ${DEPLOY_DIR_IMAGE}/${IMAGE_NAME}.grub.cfg ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	sed -i -e "s,default=localboot,default=netboot,g" ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}
