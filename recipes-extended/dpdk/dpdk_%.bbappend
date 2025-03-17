FILESEXTRAPATHS:prepend := "${THISDIR}/dpdk:"

RDEPENDS:${PN}:class-nativesdk += "python3-core"
DEPENDS:class-nativesdk = "python3-pyelftools-native"

PACKAGECONFIG = " afxdp"
PACKAGECONFIG[afxdp] = ",,libbpf"
EXTRA_OEMESON:append = " -Duse_hpet=true"

SRC_URI:append = " \
	file://reduce-queue-itr-interval-default-on-intel-nics.patch \
	"

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

BBCLASSEXTEND = "nativesdk"
MACHINE_FEATURES:remove = "qemu-usermode"
