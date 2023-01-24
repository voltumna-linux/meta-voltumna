IMAGE_LINGUAS = "en-us"
IMAGE_BOOT_FILES:remove = "${KERNEL_IMAGETYPE} ${KERNEL_DEVICETREE}"

EXTRA_IMAGE_FEATURES += " ssh-server-openssh"

WIC_CREATE_EXTRA_ARGS += " --no-fstab-update"

do_rootfs[depends] += "virtual/bootloader:do_deploy virtual/kernel:do_bundle_initramfs"
DEPENDS = "virtual/bootloader virtual/kernel"

IMAGE_INSTALL:append = "kernel-image kernel-devicetree ${MACHINE_EXTRA_RRECOMMENDS} \
	os-release bash coreutils util-linux util-linux-sfdisk glibc-utils procps psmisc ldd \
	less tzdata tzdata-europe polkit socat stress-ng sed tar xz grep findutils file \
	nano vim debianutils 96boards-tools dosfstools openssh-sftp-server nfs-utils-mount \
	iproute2 ethtool inetutils-ping inetutils-telnet net-tools libnss-resolve"
IMAGE_INSTALL:append:x86-64 = " thermald"

append_to_osrelease() {
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}/etc/os-release
	VARIANT_ID="${BPN}"
	VARIANT="Voltumna (Development)"
	MACHINE="${MACHINE}"
	__EOF__
}

remove_useless() {
	rm -f ${IMAGE_ROOTFS}/usr/bin/su ${IMAGE_ROOTFS}/usr/bin/su.*
}

use_initramfs_bundled_kernel() {
	rm -f ${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE}* 

	install -d ${IMAGE_ROOTFS}/usr/boot/
	cp -r ${DEPLOY_DIR_IMAGE}/${KERNEL_IMAGETYPE}-initramfs-${MACHINE}-* \
		${IMAGE_ROOTFS}/usr/boot/
	rm -f ${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE} 
	ln -sr ${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE}-initramfs-${MACHINE}-* \
		${IMAGE_ROOTFS}/usr/boot/${KERNEL_IMAGETYPE} 
}

copy_etc_into_factory() {
	# Use systemd's nsswitch.conf file instead of the base-files's one
	mv ${IMAGE_ROOTFS}${datadir}/factory/etc/nsswitch.conf ${IMAGE_ROOTFS}${sysconfdir}

	rm -f ${IMAGE_ROOTFS}${sysconfdir}/ld.so.cache

	# Copy files in factory/etc e create entries accordingly
	cp -r ${IMAGE_ROOTFS}${sysconfdir} ${IMAGE_ROOTFS}${datadir}/factory/
}

compute_sum() {
	MD5SUM=$(cd ${IMAGE_ROOTFS}/usr && find -type f -exec md5sum {} \;)
	echo "$MD5SUM" >> ${IMAGE_ROOTFS}/usr/.MD5SUM.txt
	gzip ${IMAGE_ROOTFS}/usr/.MD5SUM.txt
}

# This must be the latest!
move_usr_into_osdir() {
	mkdir ${IMAGE_ROOTFS}/.osdir
	mv ${IMAGE_ROOTFS}/usr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}
	mkdir ${IMAGE_ROOTFS}/usr
	rm -f ${IMAGE_ROOTFS}/.osdir/factory ${IMAGE_ROOTFS}/.osdir/default
	ln -sr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}/ ${IMAGE_ROOTFS}/.osdir/factory
	ln -sr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}/ ${IMAGE_ROOTFS}/.osdir/default
}

ROOTFS_POSTPROCESS_COMMAND:append = " remove_useless; append_to_osrelease;"
IMAGE_PREPROCESS_COMMAND:append = " use_initramfs_bundled_kernel; copy_etc_into_factory; compute_sum; move_usr_into_osdir;"

BAD_RECOMMENDATIONS += "busybox-syslog grub-common"
inherit core-image

IMAGE_CMD:tar() {
	${IMAGE_CMD_TAR} --numeric-owner --exclude='.osdir*' -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar --transform "s;^rootfs;nfsroot;" -C ${IMAGE_ROOTFS}/.. rootfs || [ $? -eq 1 ]
	${IMAGE_CMD_TAR} --numeric-owner -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.os.tar -C ${IMAGE_ROOTFS}/.osdir ${IMAGE_NAME} || [ $? -eq 1 ]
}

IMAGE_CMD:tar:append:arm() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/boot.scr.uimg ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/uEnv.txt ${TEMPORARYDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir,voltumna,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}

IMAGE_CMD:tar:append_e500v2() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/boot.scr.uimg ${TEMPORARYDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/uEnv.txt ${TEMPORARYDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir,voltumna,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}

IMAGE_CMD:tar:append:x86-64() {
	TEMPORARYDIR=$(mktemp -d)
	mkdir -p ${TEMPORARYDIR}/tftpboot/EFI/BOOT
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${TEMPORARYDIR}/tftpboot/EFI/BOOT/bootx64.efi
	install -m 644 ${DEPLOY_DIR_IMAGE}/grub.cfg ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	sed -i -e "s,default=localboot,default=netboot,g" -e "s,image=default,image=${IMAGE_NAME},g" ${TEMPORARYDIR}/tftpboot/EFI/BOOT/grub.cfg
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${TEMPORARYDIR}/ tftpboot || [ $? -eq 1 ]
	rm -fr ${TEMPORARYDIR}
}
