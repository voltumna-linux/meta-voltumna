IMAGE_LINGUAS = "en-us"
IMAGE_BOOT_FILES_remove = "${KERNEL_IMAGETYPE} ${KERNEL_DEVICETREE}"

EXTRA_IMAGE_FEATURES = "ssh-server-openssh"

WIC_CREATE_EXTRA_ARGS += " --no-fstab-update"

# DEPENDS += "virtual/kernel"
# DEPENDS_append_x86-64_class-target += "grub-efi"

IMAGE_CLASSES += "extrausers"
EXTRA_USERS_PARAMS = "\
    usermod -aG shadow www; \
"

IMAGE_INSTALL_append += "kernel-image kernel-devicetree ${MACHINE_EXTRA_RRECOMMENDS} \
	bash coreutils util-linux util-linux-sfdisk glibc-utils less procps psmisc \
	tzdata tzdata-europe polkit socat stress-ng sed tar xz grep findutils file \
	nano debianutils 96boards-tools dosfstools nfs-utils-client openssh-sftp-server \
	os-update iproute2 ethtool inetutils-ping inetutils-telnet net-tools"

#python __anonymous () {
#    d.appendVarFlag('do_install', 'depends', ' ${INITRAMFS_IMAGE}:do_image_complete')
#}

copy_etc_into_factory() {
	# Use systemd's nsswitch.conf file instead of the base-files's one
	mv ${IMAGE_ROOTFS}${datadir}/factory/etc/nsswitch.conf ${IMAGE_ROOTFS}${sysconfdir}

	# Copy files in factory/etc e create entries accordingly
	cp -r ${IMAGE_ROOTFS}${sysconfdir} ${IMAGE_ROOTFS}${datadir}/factory/

#	rm -f ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/default.target \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/basic.target.wants/resize-helper.service

#	mkdir -p ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/
#	ln -s /usr/lib/systemd/system/reboot.target \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/ctrl-alt-del.target
#	ln -s /usr/lib/systemd/system/systemd-networkd.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/dbus-org.freedesktop.network1.service
#	ln -s /usr/lib/systemd/system/systemd-resolved.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/dbus-org.freedesktop.resolve1.service
#	ln -s /usr/lib/systemd/system/systemd-timesyncd.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/dbus-org.freedesktop.timesync1.service

#	mkdir -p ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/multi-user.target.wants/
#	ln -s /usr/lib/systemd/system/systemd-networkd.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/multi-user.target.wants/systemd-networkd.service
#	ln -s /usr/lib/systemd/system/systemd-resolved.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/multi-user.target.wants/systemd-resolved.service
#	ln -s /usr/lib/systemd/system/remote-fs.target \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/multi-user.target.wants/remote-fs.target

#	mkdir -p ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/sysinit.target.wants/
#	ln -s /usr/lib/systemd/system/systemd-timesyncd.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/sysinit.target.wants/systemd-timesyncd.service
	
#	mkdir -p ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/getty.target.wants/
#	ln -s /usr/lib/systemd/system/getty@.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/getty.target.wants/getty@tty1.service

#	mkdir -p ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/network-online.target.wants/
#	ln -s /usr/lib/systemd/system/systemd-networkd-wait-online.service \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/network-online.target.wants/systemd-networkd-wait-online.service

#	mkdir -p ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/sockets.target.wants/
#	ln -s /usr/lib/systemd/system/systemd-networkd.socket \
#		${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/sockets.target.wants/systemd-networkd.socket
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
	install -m 644 ${DEPLOY_DIR_IMAGE}/uEnv.txt ${TEMPORARYDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir/,,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}

IMAGE_CMD_tar_append_x86-64() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot/EFI/BOOT
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${TEMPORARYDIR}/tftpboot/EFI/BOOT/bootx64.efi
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub.cfg ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	sed -i -e "s,default=localboot,default=netboot,g" ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}
