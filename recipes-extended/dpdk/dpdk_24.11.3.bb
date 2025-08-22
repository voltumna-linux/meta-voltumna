include dpdk.inc

SRC_URI += " file://0001-config-meson-get-cpu_instruction_set-from-meson-opti.patch "

STABLE = "-stable"
BRANCH = "24.11"
SRCREV = "b287e404643aeab5bb5db084c142789df187844e"
S = "${WORKDIR}/git"

def get_cpu_instruction_set(bb, d):
    import re
    march = re.search(r'-march=([^\s]*)', d.getVar('CC'))
    if march:
        return march.group(1)
    else:
        return "core2"

EXTRA_OEMESON = " -Dexamples=all -Dcpu_instruction_set=${@get_cpu_instruction_set(bb, d)} "

COMPATIBLE_MACHINE = "null"
COMPATIBLE_HOST:libc-musl:class-target = "null"
COMPATIBLE_HOST:linux-gnux32 = "null"

PACKAGECONFIG ??= " "
PACKAGECONFIG[afxdp] = ",,libbpf xdp-tools"
PACKAGECONFIG[libvirt] = ",,libvirt"

RDEPENDS:${PN} += "pciutils python3-core"
RDEPENDS:${PN}-examples += "bash"
DEPENDS = "numactl python3-pyelftools-native"

inherit meson pkgconfig

INSTALL_PATH = "${prefix}/share/dpdk"

do_install:append(){
    # remove  source files
    rm -rf ${D}/${INSTALL_PATH}/examples/*

    # Install examples
    install -m 0755 -d ${D}/${INSTALL_PATH}/examples/
    for dirname in ${B}/examples/dpdk-*
    do
        if [ ! -d ${dirname} ] && [ -x ${dirname} ]; then
            install -m 0755 ${dirname} ${D}/${INSTALL_PATH}/examples/
        fi
    done

}

PACKAGES =+ "${PN}-examples ${PN}-tools"

FILES:${PN} += " ${bindir}/dpdk-testpmd \
		 ${bindir}/dpdk-proc-info \
		 ${libdir}/*.so* \
		 ${libdir}/dpdk/pmds-24.1/*.so* \
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

CVE_PRODUCT = "data_plane_development_kit"

INSANE_SKIP:${PN} = "dev-so"
