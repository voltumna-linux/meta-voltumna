LICENSE = "MIT"
IMAGE_LINGUAS = "en-us"
IMAGE_BOOT_FILES_remove = "${KERNEL_IMAGETYPE} ${KERNEL_DEVICETREE}"

IMAGE_FEATURES = "bash-completion-pkgs ssh-server-openssh"

WIC_CREATE_EXTRA_ARGS += " --no-fstab-update"

IMAGE_INSTALL_append += "os-release systemd-journal-upload bash coreutils util-linux util-linux-sfdisk \
	glibc-utils procps psmisc ldd less tzdata tzdata-europe polkit lsof socat stress-ng sed tar xz \
	grep gawk findutils file nano vim debianutils 96boards-tools dosfstools openssh-sftp-server gzip \
	nfs-utils-client iproute2 ethtool inetutils-ping inetutils-telnet net-tools curl libnss-resolve \
	strace ltrace gdb libasan libubsan e2fsprogs-mke2fs"
IMAGE_INSTALL:append:x86 = " thermald liblsan libtsan nvme-cli"
IMAGE_INSTALL:append:x86-64 = " thermald liblsan libtsan nvme-cli"

copy_etc_into_factory() {
	# Use systemd's nsswitch.conf file instead of the base-files's one
	mv ${IMAGE_ROOTFS}${datadir}/factory/etc/nsswitch.conf ${IMAGE_ROOTFS}${sysconfdir}

	rm ${IMAGE_ROOTFS}${sysconfdir}/ld.so.cache

	# Copy files in factory/etc e create entries accordingly
	install -d ${IMAGE_ROOTFS}${datadir}/factory/
	cp -r ${IMAGE_ROOTFS}${sysconfdir} ${IMAGE_ROOTFS}${datadir}/factory/
}

remove_useless() {
	rm -f ${IMAGE_ROOTFS}/usr/bin/su ${IMAGE_ROOTFS}/usr/bin/su.*
}

disable_upload() {
        rm -f ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/multi-user.target.wants/systemd-journal-upload.service
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

append_to_osrelease() {
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}/etc/os-release
	VARIANT_ID="${BPN}"
	VARIANT="${VARIANT}"
	MACHINE="${MACHINE}"
	ARCHITECTURE="${DEFAULTTUNE}"
	__EOF__
}

ROOTFS_POSTPROCESS_COMMAND_append += " remove_useless; disable_upload; append_to_osrelease;"
IMAGE_PREPROCESS_COMMAND_append += " use_initramfs_bundled_kernel; copy_etc_into_factory; compute_sum; move_usr_into_osdir;"

BAD_RECOMMENDATIONS += "busybox-syslog grub-common"
inherit core-image

IMAGE_CMD_tar() {
	${IMAGE_CMD_TAR} --numeric-owner --exclude='.osdir*' -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar --transform "s;^rootfs;nfsroot;" -C ${IMAGE_ROOTFS}/.. rootfs || [ $? -eq 1 ]
	${IMAGE_CMD_TAR} --numeric-owner -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.os.tar -C ${IMAGE_ROOTFS}/.osdir ${IMAGE_NAME} || [ $? -eq 1 ]
}

IMAGE_CMD_tar_append_arm() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/boot.scr.uimg ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/uEnv.txt ${TEMPORARYDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir,voltumna,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}

IMAGE_CMD_tar_append_ppce500v2() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/boot.scr.uimg ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/uEnv.txt ${TEMPORARYDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir,voltumna,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}

IMAGE_CMD_tar_append_x86() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot/EFI/BOOT
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${TEMPORARYDIR}/tftpboot/EFI/BOOT/bootx64.efi
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub.cfg ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	sed -i -e "s,default=localboot,default=netboot,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}

IMAGE_CMD_tar_append_x86-64() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot/EFI/BOOT
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${TEMPORARYDIR}/tftpboot/EFI/BOOT/bootx64.efi
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub.cfg ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	sed -i -e "s,default=localboot,default=netboot,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}
