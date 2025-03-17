include hamamatsu.inc

inherit module

SRC_URI:append = " \
	file://activesilicon.conf \
	"

MAKE_TARGETS = "build"

do_compile() {
    cd ${S}/usr/local/activesilicon/source/driver/mdadrv/linux/
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake -f Makefile \
           KDIR=${STAGING_KERNEL_DIR}   \
           KERNEL_VERSION=${KERNEL_VERSION}    \
           CC="${KERNEL_CC}" LD="${KERNEL_LD}" \
           AR="${KERNEL_AR}" \
           O=${STAGING_KERNEL_BUILDDIR} \
           KBUILD_EXTRA_SYMBOLS="${KBUILD_EXTRA_SYMBOLS}" \
           ${MAKE_TARGETS}
}

FILES:${PN} += " \
	${sysconfdir}/udev/rules.d \
	${sysconfdir}/modules-load.d \
	"

do_install() {
    cd ${S}/usr/local/activesilicon/source/driver/mdadrv/linux/
    install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc
    install -m 0644 asl*/*.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc

    install -d ${D}${sysconfdir}/modules-load.d/
    install -m 0644 ${WORKDIR}/activesilicon.conf ${D}${sysconfdir}/modules-load.d/activesilicon.conf.disabled

#    install -d ${D}${sysconfdir}/udev/rules.d/
#    install -m 0644 aslenum/system/activesilicon.rules ${D}${sysconfdir}/udev/rules.d/
}

do_extract_data() {
	cd ${S}; ar -xv ${WORKDIR}/DCAM-API_Lite_for_Linux_v24.4.6764/api/driver/firebird/x86_64/as-fbd-linux-ham_3.2.1-1_amd64.deb
	rm debian-binary
	cd ${S}; tar -zxvf ${S}/control.tar.gz; rm ${S}/control.tar.gz
	cd ${S}; tar -zxvf ${S}/data.tar.gz; rm ${S}/data.tar.gz
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}
