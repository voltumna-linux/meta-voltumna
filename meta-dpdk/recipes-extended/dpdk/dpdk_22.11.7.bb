include dpdk.inc

SRC_URI += " \
            file://0001-meson.build-march-and-mcpu-already-passed-by-Yocto-21.11.patch \
"

STABLE = "-stable"
BRANCH = "22.11"
SRCREV = "077a7044cc5b2533410f691c8db6fb4f6667b1ca"

# kernel module is provide by dpdk-module recipe, so disable here
EXTRA_OEMESON = " -Denable_kmods=false \
                -Dexamples=all \
"

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
		 ${libdir}/dpdk/pmds-23.0/*.so* \
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
