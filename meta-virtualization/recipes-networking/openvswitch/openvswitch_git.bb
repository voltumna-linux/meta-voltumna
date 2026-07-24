require openvswitch.inc

DEPENDS += "virtual/kernel"

PACKAGE_ARCH = "${MACHINE_ARCH}"

RDEPENDS:${PN}-ptest += "\
	python3-logging python3-syslog python3-io python3-core \
	python3-fcntl python3-shell python3-xml python3-math \
	python3-datetime python3-netclient python3 sed \
	ldd perl-module-socket perl-module-carp perl-module-exporter \
	perl-module-xsloader python3-netserver python3-threading \
	python3-resource findutils which diffutils \
	"

PV = "3.7.1"
CVE_VERSION = "3.5.0"

FILESEXTRAPATHS:append := "${THISDIR}/${PN}-git:"

SRCREV = "04b05b31ade4d903589a90a14861730562285be7"
SRC_URI += "git://github.com/openvswitch/ovs.git;protocol=https;branch=branch-3.7 \
            file://run-ptest \
            file://disable_m4_check.patch \
            file://systemd-update-tool-paths.patch \
            file://systemd-create-runtime-dirs.patch \
            file://Makefile.am-set-the-python3-interpreter-with-usr-bin.patch \
           "

LIC_FILES_CHKSUM = "file://LICENSE;md5=1ce5d23a6429dff345518758f13aaeab"

PACKAGECONFIG ?= "libcap-ng"
PACKAGECONFIG[dpdk] = "--with-dpdk=shared,,dpdk,dpdk"
PACKAGECONFIG[libcap-ng] = "--enable-libcapng,--disable-libcapng,libcap-ng,"
PACKAGECONFIG[ssl] = ",--disable-ssl,openssl,"

CVE_STATUS[CVE-2023-5366] = "fixed-version: Fixed in 3.2.2, NVD tracks this as version-less vulnerability"

# Don't compile kernel modules by default since it heavily depends on
# kernel version. Use the in-kernel module for now.
# distro layers can enable with EXTRA_OECONF_pn_openvswitch += ""
# EXTRA_OECONF += "--with-linux=${STAGING_KERNEL_BUILDDIR} --with-linux-source=${STAGING_KERNEL_DIR} KARCH=${TARGET_ARCH}"

# silence a warning
FILES:${PN} += "/lib/modules"

inherit ptest

EXTRA_OEMAKE += "TEST_DEST=${D}${PTEST_PATH} TEST_ROOT=${PTEST_PATH}"

do_install_ptest() {

    install -d ${D}${PTEST_PATH}/tests/

    install -m 0644 ${B}/tests/atlocal ${B}/tests/atconfig ${D}${PTEST_PATH}/tests/

    # Copy test binaries into the ptest directory, preserving subdirectory structure.
    # Use -maxdepth 2 because subdirectories like oss-fuzz/ are not enabled by default;
    # when enabled, their binaries (e.g., ./oss-fuzz/oss) need to be copied as well.
    cd ${B}/tests && find . -maxdepth 2 -type f -executable | xargs -I {} cp --parents {} ${D}${PTEST_PATH}/tests/
    cd ${S}/tests && find . -maxdepth 1 -name '*.at' | xargs -I {} cp --parents {} ${D}${PTEST_PATH}/tests/
    cd ${S}/tests && find . -maxdepth 1 -type f -executable | xargs -I {} cp --parents {} ${D}${PTEST_PATH}/tests/

    cd ${S}/tests && find . -maxdepth 1 -name '*.py' -exec install -m 0755 {} ${D}${PTEST_PATH}/tests/ \;

    install -D -m 0644 ${S}/vswitchd/vswitch.ovsschema ${D}${PTEST_PATH}/vswitchd/vswitch.ovsschema

    install -D -m 0755 ${S}/utilities/checkpatch.py ${D}${PTEST_PATH}/utilities/checkpatch.py
    install -D -m 0644 ${S}/utilities/ovs-pcap.in ${D}${PTEST_PATH}/utilities/ovs-pcap.in
    install -D -m 0644 ${S}/utilities/ovs-pki.in  ${D}${PTEST_PATH}/utilities/ovs-pki.in

    install -D -m 0644 ${S}/python/test_requirements.txt ${D}${PTEST_PATH}/python/test_requirements.txt
    install -m 0644 ${S}/tests/idltest.ovsschema ${D}${PTEST_PATH}/tests/
    install -m 0644 ${S}/tests/idltest2.ovsschema ${D}${PTEST_PATH}/tests/
    install -m 0644 ${S}/AUTHORS.rst ${D}${PTEST_PATH}/
    install -D -m 0644 ${S}/build-aux/check-structs ${D}${PTEST_PATH}/build-aux/check-structs

    # Symlink vtep.ovsschema to the path expected by ptest; the actual file is
    # already installed by the main openvswitch package.
    install -d ${D}${PTEST_PATH}/vtep
    ln -sf /usr/share/openvswitch/vtep.ovsschema ${D}${PTEST_PATH}/vtep/vtep.ovsschema

    sed  -i \
         -e 's|PYTHON=.*|PYTHON="python3"|' \
         -e 's|PYTHONPATH=.*|PYTHONPATH=/usr/share/openvswitch/python:${PTEST_PATH}/tests:$PYTHONPATH|' \
         -e 's|EGREP=.*|EGREP='"'"'grep -E'"'"'|g' \
         -e 's|CFLAGS=.*|CFLAGS='"'"' '"'"'|g' \
         ${D}${PTEST_PATH}/tests/atlocal

    sed -i \
        -e "s|^at_testdir=.*|at_testdir='${PTEST_PATH}'|" \
        -e "s|^abs_builddir=.*|abs_builddir='${PTEST_PATH}'|" \
        -e "s|^at_srcdir=.*|at_srcdir='${PTEST_PATH}/tests'|" \
        -e "s|^abs_srcdir=.*|abs_srcdir='${PTEST_PATH}/tests'|" \
        -e "s|^at_top_srcdir=.*|at_top_srcdir='${PTEST_PATH}'|" \
        -e "s|^abs_top_srcdir=.*|abs_top_srcdir='${PTEST_PATH}'|" \
        -e "s|^at_top_build_prefix=.*|at_top_build_prefix='${PTEST_PATH}'|" \
        -e "s|^abs_top_builddir=.*|abs_top_builddir='${PTEST_PATH}'|" \
         ${D}${PTEST_PATH}/tests/atconfig

    sed -i \
        -e "s|ovs-appctl-bashcomp\.bash|/etc/bash_completion.d/ovs-appctl-bashcomp\.bash|g" \
        -e "s|ovs-vsctl-bashcomp\.bash|/etc/bash_completion.d/ovs-vsctl-bashcomp\.bash|g"   \
        -e "s|^\(.*config\.log.*\)|#\1|g" \
         ${D}${PTEST_PATH}/tests/testsuite
}
RDEPENDS:${PN}-ptest += " ${PN}-testcontroller"
RDEPENDS:${PN}-ptest += "python3-packaging python3-setuptools"
