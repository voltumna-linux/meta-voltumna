include dpdk.inc

SRC_URI += " file://0001-config-meson-get-cpu_instruction_set-from-meson-opti.patch"

STABLE = "-stable"
BRANCH = "25.11"
SRCREV = "27757d03e981a1946434e9bf4c9cfb1ab7e03546"

PACKAGES =+ "${PN}-examples ${PN}-tools"

FILES:${PN} += " ${bindir}/dpdk-testpmd \
		 ${bindir}/dpdk-proc-info \
		 ${libdir}/*.so* \
		 ${libdir}/dpdk/pmds-26.0/*.so* \
		 "
FILES:${PN}-examples = " \
	${prefix}/share/dpdk/examples/* \
	"

FILES:${PN}-tools = " \
    ${bindir}/dpdk-pdump \
    ${bindir}/dpdk-test \
    ${bindir}/dpdk-test-* \
    ${bindir}/dpdk-*.py \
    "

INSANE_SKIP:${PN} = "dev-so"
