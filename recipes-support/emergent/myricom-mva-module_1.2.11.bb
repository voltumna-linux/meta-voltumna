include emergent.inc

inherit module

RPROVIDES_${PN} += "kernel-module-myricom-mva"

SRC_URI_append = " \
	file://Kbuild \
	file://mal_checks.h \
	file://90-myri-mva.rules \
	file://myri-mva.conf.disabled \
	"

do_configure_append() {
	cp ${WORKDIR}/Kbuild ${S}/opt/EVT/myricom_mva/src/driver/linux/kbuild/
	cp ${WORKDIR}/mal_checks.h ${S}/opt/EVT/myricom_mva/src/driver/linux/
}

do_compile() {
	cd ${S}/opt/EVT/myricom_mva/src/driver/linux
	unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS
	oe_runmake -C ${STAGING_KERNEL_BUILDDIR} \
		M=${S}/opt/EVT/myricom_mva/src/driver/linux/kbuild \
		KDIR=${STAGING_KERNEL_DIR}   \
		KERNEL_VERSION=${KERNEL_VERSION}    \
		CC="${KERNEL_CC}" LD="${KERNEL_LD}" \
		AR="${KERNEL_AR}" \
		O=${STAGING_KERNEL_BUILDDIR} \
		KBUILD_EXTRA_SYMBOLS="${KBUILD_EXTRA_SYMBOLS}" \
		EXTRA_CFLAGS="-DMAL_KERNEL -DMX_THREAD_SAFE=1 \
			-DMYRI_DRIVER=myri_mva -DMYRI_DRIVER_SHORT_NAME=myri_mva \
			-DLINUX_DISTRO_UBUNTU=0 -DLINUX_DISTRO_REDHAT=1 \
				-DLINUX_DISTRO=0 -DREDHAT_VERSION=0 \
			-I${S}/opt/EVT/myricom_mva/src/driver/linux/ \
			-I${S}/opt/EVT/myricom_mva/src/driver/common \
			-I${S}/opt/EVT/myricom_mva/src/common \
			-I${S}/opt/EVT/myricom_mva/src/common/fapi"
}

FILES_${PN} += " \
	${sysconfdir}/udev/rules.d \
	${sysconfdir}/modules-load.d \
	"

do_install() {
	install -d ${D}${sysconfdir}/modules-load.d/
	install -m 0644 ${WORKDIR}/myri-mva.conf.disabled \
		${D}${sysconfdir}/modules-load.d/

	cd ${S}/./opt/EVT/myricom_mva/src/driver/linux/kbuild/
	install -d ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc
	install -m 0644 myri_mva.ko ${D}${nonarch_base_libdir}/modules/${KERNEL_VERSION}/kernel/misc

	install -d ${D}${sysconfdir}/udev/rules.d/
	install -m 0644 ${WORKDIR}/*.rules ${D}${sysconfdir}/udev/rules.d/
}
