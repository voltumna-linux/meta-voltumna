include dpdk.inc

SRC_URI += " file://0001-config-meson-get-cpu_instruction_set-from-meson-opti.patch"

STABLE = "-stable"
BRANCH = "25.11"
SRCREV = "8f56626b51efca87ac312d04bcd90935020b1e7f"

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
