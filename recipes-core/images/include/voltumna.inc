LICENSE = "MIT"
IMAGE_LINGUAS = "en-us"
IMAGE_BOOT_FILES:remove = "${KERNEL_IMAGETYPE} ${KERNEL_DEVICETREE}"

IMAGE_FEATURES += " bash-completion-pkgs ssh-server-openssh"

WIC_CREATE_EXTRA_ARGS += " --no-fstab-update"

do_rootfs[depends] += "virtual/bootloader:do_deploy virtual/kernel:do_bundle_initramfs"
DEPENDS = "virtual/bootloader virtual/kernel"

ROOTFS_BOOTSTRAP_INSTALL:remove = "run-postinsts"
IMAGE_INSTALL:append = "kernel-image kernel-devicetree ${MACHINE_EXTRA_RRECOMMENDS} \
	os-release systemd-journal-upload bash coreutils util-linux util-linux-sfdisk glibc-utils \
	procps psmisc ldd less tzdata tzdata-europe polkit lsof socat stress-ng sed tar xz grep gawk \
	findutils file nano vim debianutils 96boards-tools dosfstools openssh-sftp-server gzip \
	nfs-utils-client iproute2 iproute2-ip iproute2-devlink ethtool inetutils-ping inetutils-telnet \
	net-tools curl libnss-resolve strace ltrace gdb libasan libubsan e2fsprogs-mke2fs btop picocom"
IMAGE_INSTALL:append:x86 = " thermald liblsan libtsan linux-firmware-ice nvme-cli"
IMAGE_INSTALL:append:x86-64 = " thermald liblsan libtsan linux-firmware-ice nvme-cli"

append_to_osrelease() {
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}/etc/os-release
	VARIANT_ID="${BPN}"
	VARIANT="${VARIANT}"
	MACHINE="${MACHINE}"
	ARCHITECTURE="${DEFAULTTUNE}"
	__EOF__
}

remove_useless() {
	rm -f ${IMAGE_ROOTFS}/usr/bin/su ${IMAGE_ROOTFS}/usr/bin/su.*
}

disable_upload() {
	rm -f ${IMAGE_ROOTFS}${sysconfdir}/systemd/system/multi-user.target.wants/systemd-journal-upload.service
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
	rm -f ${IMAGE_ROOTFS}${sysconfdir}/ld.so.cache

	# Copy files in factory/etc e create entries accordingly
	install -d ${IMAGE_ROOTFS}${datadir}/factory/
	cp -r ${IMAGE_ROOTFS}${sysconfdir} ${IMAGE_ROOTFS}${datadir}/factory/
        rm -f ${IMAGE_ROOTFS}${datadir}/factory/etc/systemd/system/basic.target.wants/resize-helper.service
}

compute_sum() {
	rm -f ${IMAGE_ROOTFS}/usr/.MD5SUM.txt*
	MD5SUM=$(cd ${IMAGE_ROOTFS}/usr && find -type f -exec md5sum {} \;)
	echo "$MD5SUM" >> ${IMAGE_ROOTFS}/usr/.MD5SUM.txt
	gzip ${IMAGE_ROOTFS}/usr/.MD5SUM.txt
}

complete_uboot_bootloader_conf() {
	sed -e "s,@IMAGE_NAME@,${IMAGE_NAME},g" ${DEPLOY_DIR_IMAGE}/uEnv.txt > ${DEPLOY_DIR_IMAGE}/uEnv-${IMAGE_LINK_NAME}.txt
}

complete_grub_bootloader_conf() {
	sed -e "s,@IMAGE_NAME@,${IMAGE_NAME},g" ${DEPLOY_DIR_IMAGE}/grub.cfg  > ${DEPLOY_DIR_IMAGE}/grub-${IMAGE_LINK_NAME}.cfg
}

move_usr_into_osdir() {
	rm -fr ${IMAGE_ROOTFS}/.osdir
	mkdir ${IMAGE_ROOTFS}/.osdir
	mv ${IMAGE_ROOTFS}/usr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}
	mkdir ${IMAGE_ROOTFS}/usr
	rm -f ${IMAGE_ROOTFS}/.osdir/factory ${IMAGE_ROOTFS}/.osdir/default
	ln -sr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}/ ${IMAGE_ROOTFS}/.osdir/factory
	ln -sr ${IMAGE_ROOTFS}/.osdir/${IMAGE_NAME}/ ${IMAGE_ROOTFS}/.osdir/default
}

ROOTFS_POSTPROCESS_COMMAND:append = " remove_useless; disable_upload; append_to_osrelease;"
IMAGE_PREPROCESS_COMMAND:append = " use_initramfs_bundled_kernel; copy_etc_into_factory; compute_sum; move_usr_into_osdir;"
IMAGE_PREPROCESS_COMMAND:append:arm = " complete_uboot_bootloader_conf;"
IMAGE_PREPROCESS_COMMAND:append:mvme2500 = " complete_uboot_bootloader_conf;"
IMAGE_PREPROCESS_COMMAND:append:x86-64 = " complete_grub_bootloader_conf;"
IMAGE_PREPROCESS_COMMAND:append:x86 = " complete_grub_bootloader_conf;"

BAD_RECOMMENDATIONS += "busybox-syslog grub-common"
inherit core-image

IMAGE_CMD:tar:append() {
        true
	${IMAGE_CMD_TAR} --numeric-owner --exclude='.osdir*' -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar --transform 's;^rootfs;nfsroot;' -C ${IMAGE_ROOTFS}/.. rootfs || [ $? -eq 1 ]
	${IMAGE_CMD_TAR} --numeric-owner -cf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.os.tar -C ${IMAGE_ROOTFS}/.osdir ${IMAGE_NAME} || [ $? -eq 1 ]
}

IMAGE_CMD:tar:append:arm() {
	rm -fr ${WORKDIR}/tftpboot
	mkdir -p ${WORKDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/boot.scr.uimg ${WORKDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/uEnv-${IMAGE_LINK_NAME}.txt ${WORKDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir,voltumna,g" ${WORKDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${WORKDIR} tftpboot || [ $? -eq 1 ]
	rm -fr ${WORKDIR}/tftpboot
}

IMAGE_CMD:tar:append:ppce500v2() {
	rm -fr ${WORKDIR}/tftpboot
	mkdir -p ${WORKDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/boot.scr.uimg ${WORKDIR}/tftpboot
	install -m 644 ${DEPLOY_DIR_IMAGE}/uEnv-${IMAGE_LINK_NAME}.txt ${WORKDIR}/tftpboot/uEnv.txt
	sed -i -e "s,\.osdir,voltumna,g" ${WORKDIR}/tftpboot/uEnv.txt
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${WORKDIR} tftpboot || [ $? -eq 1 ]
	rm -fr ${WORKDIR}/tftpboot
}

IMAGE_CMD:tar:append:x86() {
	rm -fr ${WORKDIR}/tftpboot
	if [ -f ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ]; then
		mkdir -p ${WORKDIR}/tftpboot/EFI/BOOT
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${WORKDIR}/tftpboot/EFI/BOOT/bootx64.efi
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-${IMAGE_LINK_NAME}.cfg ${WORKDIR}/tftpboot/EFI/BOOT/grub.cfg
		sed -i -e "s,default=localboot,default=netboot,g" ${WORKDIR}/tftpboot/FI/BOOT/grub.cfg
	fi
	if [ -f ${DEPLOY_DIR_IMAGE}/grub-bootx86.pxe ]; then
		mkdir -p ${WORKDIR}/tftpboot/BOOT
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-bootx86.pxe ${WORKDIR}/tftpboot/BOOT/bootx86.pxe
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-${IMAGE_LINK_NAME}.cfg ${WORKDIR}/tftpboot/BOOT/grub.cfg
		sed -i -e "s,default=localboot,default=netboot,g" ${WORKDIR}/tftpboot/BOOT/grub.cfg
	fi
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${WORKDIR} tftpboot || [ $? -eq 1 ]
	rm -fr ${WORKDIR}/tftpboot
}

IMAGE_CMD:tar:append:x86-64() {
	rm -fr ${WORKDIR}/tftpboot
	if [ -f ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ]; then
		mkdir -p ${WORKDIR}/tftpboot/EFI/BOOT
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-efi-bootx64.efi ${WORKDIR}/tftpboot/EFI/BOOT/bootx64.efi
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-${IMAGE_LINK_NAME}.cfg ${WORKDIR}/tftpboot/EFI/BOOT/grub.cfg
		sed -i -e "s,default=localboot,default=netboot,g" ${WORKDIR}/tftpboot/EFI/BOOT/grub.cfg
	fi
	if [ -f ${DEPLOY_DIR_IMAGE}/grub-bootx86.pxe ]; then
		mkdir -p ${WORKDIR}/tftpboot/BOOT
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-bootx86.pxe ${WORKDIR}/tftpboot/BOOT/bootx86.pxe
		install -m 644 ${DEPLOY_DIR_IMAGE}/grub-${IMAGE_LINK_NAME}.cfg ${WORKDIR}/tftpboot/BOOT/grub.cfg
		sed -i -e "s,default=localboot,default=netboot,g" ${WORKDIR}/tftpboot/BOOT/grub.cfg
	fi
	${IMAGE_CMD_TAR} --numeric-owner -rf ${IMGDEPLOYDIR}/${IMAGE_NAME}${IMAGE_NAME_SUFFIX}.net.tar -C ${WORKDIR} tftpboot || [ $? -eq 1 ]
	rm -fr ${WORKDIR}/tftpboot
}
