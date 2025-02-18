include edt-pdv.inc

inherit module

RPROVIDES:${PN} += "kernel-module-edt"
RDEPENDS:kernel-module-edt += "edt-utils"

SRC_URI:append = " \
	file://Makefile \
	file://driver_rules.mk.patch \
	"

MAKE_TARGETS = "build"

do_compile() {
    cd ${S}/pdv/module
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake -f ${WORKDIR}/Makefile \
           KDIR=${STAGING_KERNEL_DIR}   \
           KERNEL_VERSION=${KERNEL_VERSION}    \
           CC="${KERNEL_CC}" LD="${KERNEL_LD}" \
           AR="${KERNEL_AR}" \
           O=${STAGING_KERNEL_BUILDDIR} \
           KBUILD_EXTRA_SYMBOLS="${KBUILD_EXTRA_SYMBOLS}" \
           ${MAKE_TARGETS}
}

do_install() {
    cd ${S}/pdv/module
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake -f ${WORKDIR}/Makefile \
               KDIR=${STAGING_KERNEL_DIR}   \
               DEPMOD=echo MODLIB="${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}" \
               INSTALL_FW_PATH="${D}${nonarch_base_libdir}/firmware" \
               CC="${KERNEL_CC}" LD="${KERNEL_LD}" \
               O=${STAGING_KERNEL_BUILDDIR} \
               ${MODULES_INSTALL_TARGET}
}
