DESCRIPTION = "rnm-dpdk"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=02e84b7a61e84a931e51df5464bda493"

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
PACKAGE_ARCH = "${MACHINE_ARCH}"
DEPENDS:append = "librnmdpdk"

SRC_URI = " \
        https://gitlab.elettra.eu/cs/drv/mods/rnm-dpdk/-/archive/${PV}/rnm-dpdk-${PV}.tar.bz2 \
        file://rnm-dpdk.service \
	file://rnm-dpdk-conf.service \
	file://rnm-dpdk-conf.sh \
        "

SRC_URI[sha256sum] = "502b20499d1a1abf12360d418c09195d5bd0d8eee639855a364b1b5bb87b128a"

EXTRA_OEMAKE:append = " \
	RTE_SDK=${STAGING_DIR_TARGET}/usr/share/dpdk \
	EXTRA_LDFLAGS="-L${STAGING_LIBDIR} --hash-style=gnu -fuse-ld=bfd" \
	EXTRA_CFLAGS="${HOST_CC_ARCH} ${TOOLCHAIN_OPTIONS} -O3 -I${STAGING_INCDIR}" \
	CROSS="${TARGET_PREFIX}" \
        PREFIX="${D}" \
        "

FILES:${PN}:append = "${sysconfdir} ${systemd_unitdir}/system"

SYSTEMD_SERVICE:${PN} = "rnm-dpdk.service rnm-dpdk-conf.service"
SYSTEMD_AUTO_ENABLE = "enable"

do_compile() {
	oe_runmake V=1 T=rnm-dpdk
}

do_install[vardeps] += "RNM_NETIF RNM_LCORE"
do_install() {
	oe_runmake install V=1 T=rnm-dpdk

	install -d ${D}${bindir}
	install -m 0755 ${UNPACKDIR}/rnm-dpdk-conf.sh ${D}${bindir}

	install -d ${D}${systemd_system_unitdir}
	install -m 0644 ${UNPACKDIR}/rnm-dpdk.service \
		${UNPACKDIR}/rnm-dpdk-conf.service \
		${D}${systemd_system_unitdir}

	install -d ${D}${sysconfdir}
	echo "RNM_NETIF=${@d.getVar('RNM_NETIF')}" > ${D}${sysconfdir}/rnm.conf
	echo "RNM_LCORE=${@d.getVar('RNM_LCORE')}" >> ${D}${sysconfdir}/rnm.conf
	echo "RNM_DEVARGS=" >> ${D}${sysconfdir}/rnm.conf
	
	install -d ${D}${sysconfdir}/modules-load.d/
	cat <<-__EOF__ >> ${D}${sysconfdir}/modules-load.d/vfio-pci.conf
	vfio_pci
	__EOF__

	cat <<-__EOF__ >> ${D}${sysconfdir}/modules-load.d/vfio-iommu-type1.conf
	vfio_iommu_type1
	__EOF__

	install -d ${D}${sysconfdir}/modprobe.d/
	cat <<-__EOF__ >> ${D}${sysconfdir}/modprobe.d/vfio-iommu-type1.conf
	options vfio_iommu_type1 allow_unsafe_interrupts=1
	__EOF__
}

inherit systemd pkgconfig
