DESCRIPTION = "Intel(r) Data Plane Development Kit"
HOMEPAGE = "http://dpdk.org"

LICENSE = "BSD-3-Clause & LGPL-2.1-only & GPL-2.0-only"
LIC_FILES_CHKSUM = "file://license/gpl-2.0.txt;md5=b234ee4d69f5fce4486a80fdaf4a4263 \
                    file://license/lgpl-2.1.txt;md5=4b54a1fd55a448865a0b32d41598759d \
                    file://license/bsd-3-clause.txt;md5=0f00d99239d922ffd13cabef83b33444"

SRC_URI = "git://dpdk.org/git/dpdk${STABLE};protocol=https;branch=${BRANCH};tag=v${PV} \
"

def get_cpu_instruction_set(bb, d):
    import re
    march = re.search(r'-march=([^\s]*)', d.getVar('CC'))
    if march:
        return march.group(1)
    else:
        return "core2"

EXTRA_OEMESON = " -Dcpu_instruction_set=${@get_cpu_instruction_set(bb, d)}"
EXTRA_OEMESON:aarch64 = " --cross-file ${WORKDIR}/dpdk.cross"

COMPATIBLE_HOST:libc-musl:class-target = "null"
COMPATIBLE_HOST:linux-gnux32 = "null"

PACKAGECONFIG ??= "examples"
PACKAGECONFIG[afxdp] = ",,libbpf xdp-tools"
PACKAGECONFIG[examples] = "-Dexamples=all, -Dexamples=,"
PACKAGECONFIG[libvirt] = ",,libvirt"
PACKAGECONFIG[shared]  = "--default-library=shared, --default-library=static,"

RDEPENDS:${PN} += "pciutils python3-core"
RDEPENDS:${PN}-examples += "bash"
DEPENDS = "numactl python3-pyelftools-native"

inherit meson pkgconfig

INSTALL_PATH = "${prefix}/share/dpdk"

RTE_PLATFORM ?= "generic"

do_write_config:append() {
    cat >${WORKDIR}/dpdk.cross <<EOF
[properties]
platform = '${RTE_PLATFORM}'
EOF
}

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

CVE_PRODUCT = "data_plane_development_kit"
