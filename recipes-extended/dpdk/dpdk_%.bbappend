FILESEXTRAPATHS:prepend := "${THISDIR}/dpdk:"

RDEPENDS:${PN}:class-nativesdk += "python3-core"
DEPENDS:class-nativesdk = "python3-pyelftools-native"

PACKAGECONFIG = " afxdp"
PACKAGECONFIG[afxdp] = ",,libbpf"
EXTRA_OEMESON:append = " -Duse_hpet=true"

SRC_URI:append = " \
	file://reduce-queue-itr-interval-default-on-intel-nics.patch \
	"

PACKAGE_ARCH = "${MACHINE_ARCH}"

SRC_URI:append:d-e5462-x7dwu = " \
	file://0001-Remove-SSE4.2-code.patch \
	"

SRC_URI:append:d-e5472-x7dwu = " \
	file://0001-Remove-SSE4.2-code.patch \
	"

do_configure:prepend() {
	sed -i 's,.*RTE_LIBRTE_I40E_16BYTE_RX_DESC.*,#define RTE_LIBRTE_I40E_16BYTE_RX_DESC 1 \
#define RTE_LIBRTE_ICE_16BYTE_RX_DESC 1,g' \
		${S}/config/rte_config.h
}

do_install:append() {
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

BBCLASSEXTEND = "nativesdk"
MACHINE_FEATURES:remove = "qemu-usermode"
