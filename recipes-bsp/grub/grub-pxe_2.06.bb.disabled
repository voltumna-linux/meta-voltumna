require recipes-bsp/grub/grub2.inc

GRUBPLATFORM = "pc"

DEPENDS:append = " grub-native"
RDEPENDS:${PN} = "grub-common virtual-grub-bootconf"

SRC_URI += " \
           file://cfg.pxe \
          "

S = "${WORKDIR}/grub-${PV}"

PROVIDES += "virtual/bootloader"

GRUB_TARGET = "i386"
GRUB_IMAGE_PREFIX = "grub-"
GRUB_IMAGE = "bootx86.pxe"
GRUBDIR = "/BOOT"
GRUB_PREFIX = "/boot"
GRUB_FILES_PATH = "${GRUB_PREFIX}${GRUBDIR}"

inherit deploy

CACHED_CONFIGUREVARS += "ac_cv_path_HELP2MAN="

do_mkimage() {
	cd ${B}

	GRUB_MKIMAGE_MODULES="${GRUB_BUILDIN}"

	# If 'all' is included in GRUB_BUILDIN we will include all available grub2 modules
	if [ "${@ bb.utils.contains('GRUB_BUILDIN', 'all', 'True', 'False', d)}" = "True" ]; then
		bbdebug 1 "Including all available modules"
		# Get the list of all .mod files in grub-core build directory
		GRUB_MKIMAGE_MODULES=$(find ${B}/grub-core/ -type f -name "*.mod" -exec basename {} .mod \;)
	fi

	# Search for the grub.cfg on the local boot media by using the
	# built in cfg.pxe file provided via this recipe
	grub-mkimage -v -c ../cfg.pxe -p ${GRUBDIR} -d ./grub-core/ \
	               -O ${GRUB_TARGET}-pc-pxe -o ./${GRUB_IMAGE_PREFIX}${GRUB_IMAGE} \
	               ${GRUB_MKIMAGE_MODULES}
}

addtask mkimage before do_install after do_compile

do_install() {
    oe_runmake 'DESTDIR=${D}' -C grub-core install

    # Remove build host references...
    find "${D}" -name modinfo.sh -type f -exec \
        sed -i \
        -e 's,--sysroot=${STAGING_DIR_TARGET},,g' \
        -e 's|${DEBUG_PREFIX_MAP}||g' \
        -e 's:${RECIPE_SYSROOT_NATIVE}::g' \
        {} +

    install -d ${D}${GRUB_FILES_PATH}
    install -m 644 ${B}/${GRUB_IMAGE_PREFIX}${GRUB_IMAGE} ${D}${GRUB_FILES_PATH}/${GRUB_IMAGE}

    rm -rf ${D}/usr ${D}${libdir}
}

# To include all available modules, add 'all' to GRUB_BUILDIN
GRUB_BUILDIN ?= "boot linux ext2 fat serial part_msdos part_gpt normal \
                 iso9660 configfile search loadenv test reboot echo net \
		 chain pxe tftp biosdisk"

do_deploy() {
	install -m 644 ${B}/${GRUB_IMAGE_PREFIX}${GRUB_IMAGE} ${DEPLOYDIR}
}

addtask deploy after do_install before do_build

FILES:${PN} = "${libdir}/grub/${GRUB_TARGET}-${GRUB_PLATFORM} \
               ${datadir}/grub \
               ${GRUB_FILES_PATH}/${GRUB_IMAGE} \
               "

# 64-bit binaries are expected for the bootloader with an x32 userland
INSANE_SKIP:${PN}:append:linux-gnux32 = " arch"
INSANE_SKIP:${PN}-dbg:append:linux-gnux32 = " arch"
INSANE_SKIP:${PN}:append:linux-muslx32 = " arch"
INSANE_SKIP:${PN}-dbg:append:linux-muslx32 = " arch"
