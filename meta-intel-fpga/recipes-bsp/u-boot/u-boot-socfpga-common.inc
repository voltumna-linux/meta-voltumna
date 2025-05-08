HOMEPAGE = "http://www.denx.de/wiki/U-Boot/WebHome"
SECTION = "bootloaders"

DEPENDS = "coreutils-native bc-native bison-native dtc-native flex-native"
DEPENDS:append = " python3-setuptools-native swig-native u-boot-mkimage-native"
DEPENDS:append = " u-boot-tools virtual/kernel"

DEPENDS:append:agilex7_dk_si_agf014ea = " arm-trusted-firmware bash"
DEPENDS:append:agilex7_dk_si_agf014eb = " arm-trusted-firmware bash"
DEPENDS:append:agilex7_dk_si_agi027fb = " arm-trusted-firmware bash"
DEPENDS:append:agilex7_dk_si_agi027fa = " arm-trusted-firmware bash"
DEPENDS:append:agilex7_dk_dev_agf027f1es = " arm-trusted-firmware bash"
DEPENDS:append:agilex7_dk_dev_agm039fes = " arm-trusted-firmware bash"
DEPENDS:append:agilex5 = " arm-trusted-firmware bash"
DEPENDS:append:stratix10 = " arm-trusted-firmware bash"
DEPENDS:append:n5x = " arm-trusted-firmware bash"

COMPILE_PREPEND_FILES:agilex7_dk_si_agf014ea = " bl31.bin "
COMPILE_PREPEND_FILES:agilex7_dk_si_agf014eb = " bl31.bin "
COMPILE_PREPEND_FILES:agilex7_dk_si_agi027fb = " bl31.bin "
COMPILE_PREPEND_FILES:agilex7_dk_si_agi027fa = " bl31.bin "
COMPILE_PREPEND_FILES:agilex7_dk_dev_agf027f1es = " bl31.bin "
COMPILE_PREPEND_FILES:agilex7_dk_dev_agm039fes = " bl31.bin "
COMPILE_PREPEND_FILES:agilex5 = " bl31.bin "
COMPILE_PREPEND_FILES:stratix10 = " bl31.bin "
COMPILE_PREPEND_FILES:n5x = " bl31.bin Image linux.dtb u-boot.txt "
COMPILE_PREPEND_FILES:arria10 = " Image "

DEPLOY_APPEND_FILES:agilex7_dk_si_agf014ea = ""
DEPLOY_APPEND_FILES:agilex7_dk_si_agf014eb = ""
DEPLOY_APPEND_FILES:agilex7_dk_si_agi027fb = ""
DEPLOY_APPEND_FILES:agilex7_dk_si_agi027fa = ""
DEPLOY_APPEND_FILES:agilex7_dk_dev_agf027f1es = ""
DEPLOY_APPEND_FILES:agilex7_dk_dev_agm039fes = ""
DEPLOY_APPEND_FILES:agilex5 = ""
DEPLOY_APPEND_FILES:stratix10 = ""
DEPLOY_APPEND_FILES:n5x = " kernel.itb "

LICENSE = "GPL-2.0-or-later"
LIC_FILES_CHKSUM ?= "file://Licenses/README;md5=30503fd321432fc713238f582193b78e"
PE = "1"

UBOOT_REPO ?= "git://github.com/altera-opensource/u-boot-socfpga.git"
UBOOT_PROT ?= "https"

UBOOT_VERSION_PREFIX ?= "socfpga_"
UBOOT_VERSION ?= "v2020.07"
UBOOT_BRANCH ?= "${UBOOT_VERSION_PREFIX}${UBOOT_VERSION}"

SRCREV ?= "${AUTOREV}"
PV:append = "+git${SRCPV}"

S = "${WORKDIR}/git"
B = "${WORKDIR}/build"

RPROVIDES:${PN} = "u-boot"

SRC_URI = "${UBOOT_REPO};protocol=${UBOOT_PROT};branch=${UBOOT_BRANCH}"

do_compile:prepend() {
	if [ -n "${COMPILE_PREPEND_FILES}" ]; then
		if [ -n "${UBOOT_CONFIG}" ]; then
			for config in ${UBOOT_MACHINE}; do
				i=$(expr $i + 1);
				for type in ${UBOOT_CONFIG}; do
					j=$(expr $j + 1);
					if [ $j -eq $i ]; then
						for file in ${COMPILE_PREPEND_FILES}; do
							if [ "${file}" = "linux.dtb" ]; then
								cp ${DEPLOY_DIR_IMAGE}/socfpga_${MACHINE}_socdk.dtb ${B}/${config}/linux.dtb
								cp ${DEPLOY_DIR_IMAGE}/socfpga_${MACHINE}_socdk.dtb ${S}/linux.dtb
							elif [ "${file}" = "u-boot.txt" ]; then
								cp ${DEPLOY_DIR_IMAGE}/u-boot.txt ${B}/${config}/u-boot.txt
								cp ${DEPLOY_DIR_IMAGE}/u-boot.txt ${S}/u-boot.txt
							else
								cp ${DEPLOY_DIR_IMAGE}/${file} ${B}/${config}/${file}
								cp ${DEPLOY_DIR_IMAGE}/${file} ${S}/${file}
							fi
						done
					fi
				done
				unset j
			done
			unset i
		else
			for file in ${COMPILE_PREPEND_FILES}; do
				if [ "${file}" = "linux.dtb" ]; then
					cp ${DEPLOY_DIR_IMAGE}/socfpga_${MACHINE}_socdk.dtb ${B}/${config}/linux.dtb
					cp ${DEPLOY_DIR_IMAGE}/socfpga_${MACHINE}_socdk.dtb ${S}/linux.dtb
				elif [ "${file}" = "u-boot.txt" ]; then
					cp ${DEPLOY_DIR_IMAGE}/u-boot.txt ${B}/${config}/u-boot.txt
					cp ${DEPLOY_DIR_IMAGE}/u-boot.txt ${S}/u-boot.txt
				else
					cp ${DEPLOY_DIR_IMAGE}/${file} ${B}/${config}/${file}
					cp ${DEPLOY_DIR_IMAGE}/${file} ${S}/${file}
				fi
			done
		fi
	fi
}

do_install:append() {
	if [ "${MACHINE}" = *"agilex7_"* ] || [ "${MACHINE}" = "agilex5" ] || [ "${MACHINE}" = "stratix10" ] || [ "${MACHINE}" = "n5x" ]; then
		if [ -n "${UBOOT_CONFIG}" ]; then
			for config in ${UBOOT_MACHINE}; do
				i=$(expr $i + 1);
				for type in ${UBOOT_CONFIG}; do
					j=$(expr $j + 1);
					if [ $j -eq $i ]; then
						cp ${B}/${config}/u-boot.itb ${B}/${config}/u-boot-${type}.itb
						install -D -m 644 ${B}/${config}/u-boot-${type}.itb ${D}/boot/u-boot-${type}-${PV}-${PR}.itb
						ln -sf u-boot-${type}-${PV}-${PR}.itb ${D}/boot/u-boot.itb-${type}
						ln -sf u-boot-${type}-${PV}-${PR}.itb ${D}/boot/u-boot.itb
						rm -rf  ${D}/boot/?*.img*
					fi
				done
				unset j
			done
			unset i
		else
			cp ${B}/u-boot.itb ${B}/u-boot-${UBOOT_CONFIG}.itb
			install -D -m 644 ${B}/u-boot-${config}.itb ${D}/boot/u-boot-${UBOOT_CONFIG}-${PV}-${PR}.itb
			ln -sf u-boot-${UBOOT_CONFIG}-${PV}-${PR}.itb ${D}/boot/u-boot.itb-${UBOOT_CONFIG}
			ln -sf u-boot-${UBOOT_CONFIG}-${PV}-${PR}.itb ${D}/boot/u-boot.itb
			rm -rf  ${D}/boot/?*.img*
		fi
	fi
}

do_deploy:append() {
	if [ -n "${DEPLOY_APPEND_FILES}" ]
	then
		if [ -n "${UBOOT_CONFIG}" ]
		then
			for config in ${UBOOT_MACHINE}; do
				i=$(expr $i + 1);
				for type in ${UBOOT_CONFIG}; do
					j=$(expr $j + 1);
					if [ $j -eq $i ]
					then
						for file in ${DEPLOY_APPEND_FILES}; do
							if [ "${MACHINE}" = "n5x" ]; then
								install -m 744 ${B}/${config}/${file} ${DEPLOYDIR}/${file}
							else
								:
							fi
						done
					fi
				done
				unset j
			done
			unset i
		else
			for file in ${DEPLOY_APPEND_FILES}; do
				if [ "${MACHINE}" = "n5x" ]; then
					install -m 744 ${B}/${config}/${file} ${DEPLOYDIR}/${file}
				else
					:
				fi
			done
		fi
	fi
}

require ${COREBASE}/meta/recipes-bsp/u-boot/u-boot.inc
