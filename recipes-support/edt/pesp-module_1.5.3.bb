DESCRIPTION = "Pesp module Common interface between real time apps and servers"
HOMEPAGE = "https://gitlab.elettra.eu/cs/drv/mods/pesp"
LICENSE = "CLOSED"

SRCREV = "428b57d665bb47db4a4f385eed6848c16cd7bc5c"
SRC_URI = "git://gitlab.elettra.eu/cs/drv/mods/pesp.git;protocol=https;branch=master"

S = "${WORKDIR}/git"

inherit module

DEPENDS:append = "libhimage"

RPROVIDES:${PN} += "kernel-module-pesp"

#SRC_URI:append = " \
#	file://Makefile \
#	file://driver_rules.mk.patch \
#	file://90-edt.rules  \
#	"

#MAKE_TARGETS = "build"

EXTRA_OEMAKE:append = " \
        EXTRA_CFLAGS="-I${STAGING_INCDIR}" \
        "

do_compile() {
    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
    oe_runmake KDIR=${STAGING_KERNEL_DIR}   \
           KERNEL_VERSION=${KERNEL_VERSION}    \
           CC="${KERNEL_CC}" LD="${KERNEL_LD}" \
           AR="${KERNEL_AR}" \
           O=${STAGING_KERNEL_BUILDDIR} \
           KBUILD_EXTRA_SYMBOLS="${KBUILD_EXTRA_SYMBOLS}" \
           ${MAKE_TARGETS}
}

#FILES:${PN} += " \
#	${sysconfdir}/udev/rules.d \
#	"
#
#do_install() {
#    cd ${S}/pdv/module
#    unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
#    oe_runmake -f ${WORKDIR}/Makefile \
#               KDIR=${STAGING_KERNEL_DIR}   \
#               DEPMOD=echo MODLIB="${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}" \
#               INSTALL_FW_PATH="${D}${nonarch_base_libdir}/firmware" \
#               CC="${KERNEL_CC}" LD="${KERNEL_LD}" \
#               O=${STAGING_KERNEL_BUILDDIR} \
#               ${MODULES_INSTALL_TARGET}
# 
#    install -d ${D}${sysconfdir}/udev/rules.d/
#    install -m 0644 ${WORKDIR}/*.rules ${D}${sysconfdir}/udev/rules.d/
#}
