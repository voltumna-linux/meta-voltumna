SUMMARY = "XML C Parser Library and Toolkit"
DESCRIPTION = "The XML Parser Library allows for manipulation of XML files.  Libxml2 exports Push and Pull type parser interfaces for both XML and HTML.  It can do DTD validation at parse time, on a parsed document instance or with an arbitrary DTD.  Libxml2 includes complete XPath, XPointer and Xinclude implementations.  It also has a SAX like interface, which is designed to be compatible with Expat."
HOMEPAGE = "https://gitlab.gnome.org/GNOME/libxml2"
BUGTRACKER = "http://bugzilla.gnome.org/buglist.cgi?product=libxml2"
SECTION = "libs"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://Copyright;md5=2044417e2e5006b65a8b9067b683fcf1 \
                    file://hash.c;beginline=6;endline=15;md5=96f7296605eae807670fb08947829969 \
                    file://list.c;beginline=4;endline=13;md5=cdbfa3dee51c099edb04e39f762ee907 \
                    file://trio.c;beginline=5;endline=14;md5=6c025753c86d958722ec76e94cae932e"

DEPENDS = "zlib virtual/libiconv"

inherit gnomebase

SRC_URI += "http://www.w3.org/XML/Test/xmlts20080827.tar.gz;subdir=${BP};name=testtar \
           file://libxml-64bit.patch \
           file://runtest.patch \
           file://run-ptest \
           file://python-sitepackages-dir.patch \
           file://libxml-m4-use-pkgconfig.patch \
           file://0001-Make-ptest-run-the-python-tests-if-python-is-enabled.patch \
           file://fix-execution-of-ptests.patch \
           file://CVE-2020-7595.patch \
           file://CVE-2019-20388.patch \
           file://CVE-2020-24977.patch \
           file://CVE-2021-3517.patch \
           file://CVE-2021-3537.patch \
           file://CVE-2021-3518.patch \
           file://CVE-2021-3541.patch \
           file://CVE-2022-23308.patch \
           file://CVE-2022-23308-fix-regression.patch \
           file://CVE-2022-29824-dependent.patch \
           file://CVE-2022-29824.patch \
           file://0001-Port-gentest.py-to-Python-3.patch \
           file://CVE-2016-3709.patch \
           file://CVE-2022-40303.patch \
           file://CVE-2022-40304.patch \
           file://CVE-2023-28484.patch \
           file://CVE-2023-29469.patch \
           file://CVE-2023-39615-pre.patch \
           file://CVE-2023-39615-0001.patch \
           file://CVE-2023-39615-0002.patch \
           file://CVE-2021-3516.patch \
           file://CVE-2023-45322-1.patch \
           file://CVE-2023-45322-2.patch \
           file://CVE-2024-25062-pre1.patch \
           file://CVE-2024-25062.patch \
           "

SRC_URI[archive.sha256sum] = "593b7b751dd18c2d6abcd0c4bcb29efc203d0b4373a6df98e3a455ea74ae2813"
SRC_URI[testtar.md5sum] = "ae3d1ebe000a3972afa104ca7f0e1b4a"
SRC_URI[testtar.sha256sum] = "96151685cec997e1f9f3387e3626d61e6284d4d6e66e0e440c209286c03e9cc7"

BINCONFIG = "${bindir}/xml2-config"

PACKAGECONFIG ??= "python \
    ${@bb.utils.filter('DISTRO_FEATURES', 'ipv6', d)} \
"
PACKAGECONFIG[python] = "--with-python=${PYTHON},--without-python,python3"
PACKAGECONFIG[ipv6] = "--enable-ipv6,--disable-ipv6,"

inherit autotools pkgconfig binconfig-disabled ptest features_check

inherit ${@bb.utils.contains('PACKAGECONFIG', 'python', 'python3targetconfig', '', d)}

RDEPENDS_${PN}-ptest += "bash make ${@bb.utils.contains('PACKAGECONFIG', 'python', 'libgcc python3-core python3-logging python3-shell  python3-stringold python3-threading python3-unittest ${PN}-python', '', d)}"

RDEPENDS_${PN}-python += "${@bb.utils.contains('PACKAGECONFIG', 'python', 'python3-core', '', d)}"

RDEPENDS_${PN}-ptest_append_libc-glibc = " glibc-gconv-ebcdic-us \
                                           glibc-gconv-ibm1141 \
                                           glibc-gconv-iso8859-5 \
                                           glibc-gconv-euc-jp \
                                           locale-base-en-us \
                                         "

export PYTHON_SITE_PACKAGES="${PYTHON_SITEPACKAGES_DIR}"

# WARNING: zlib is required for RPM use
EXTRA_OECONF = "--without-debug --without-legacy --with-catalog --without-docbook --with-c14n --without-lzma --with-fexceptions"
EXTRA_OECONF_class-native = "--without-legacy --without-docbook --with-c14n --without-lzma --with-zlib"
EXTRA_OECONF_class-nativesdk = "--without-legacy --without-docbook --with-c14n --without-lzma --with-zlib"
EXTRA_OECONF_linuxstdbase = "--with-debug --with-legacy --with-docbook --with-c14n --without-lzma --with-zlib"

python populate_packages_prepend () {
    # autonamer would call this libxml2-2, but we don't want that
    if d.getVar('DEBIAN_NAMES'):
        d.setVar('PKG_libxml2', '${MLPREFIX}libxml2')
}

PACKAGE_BEFORE_PN += "${PN}-utils"
PACKAGES += "${PN}-python"

FILES_${PN}-staticdev += "${PYTHON_SITEPACKAGES_DIR}/*.a"
FILES_${PN}-dev += "${libdir}/xml2Conf.sh ${libdir}/cmake/*"
FILES_${PN}-utils = "${bindir}/*"
FILES_${PN}-python = "${PYTHON_SITEPACKAGES_DIR}"

do_configure_prepend () {
	# executables take longer to package: these should not be executable
	find ${S}/xmlconf/ -type f -exec chmod -x {} \+
}

do_compile_ptest() {
        # Make sure that testapi.c is newer than gentests.py, because
        # with reproducible builds, they will both get e.g. Jan  1  1970
        # modification time from SOURCE_DATE_EPOCH and then check-am
        # might try to rebuild_testapi, which will fail even with
        # 0001-Port-gentest.py-to-Python-3.patch, because it needs
        # libxml2 module (libxml2-native dependency and correctly
        # set PYTHON_SITE_PACKAGES), it's easier to
        # just rely on pre-generated testapi.c from the release
        touch ${S}/testapi.c

	oe_runmake check-am
}

do_install_ptest () {
	cp -r ${S}/xmlconf ${D}${PTEST_PATH}
	if [ "${@bb.utils.filter('PACKAGECONFIG', 'python', d)}" ]; then
		sed -i -e 's|^\(PYTHON = \).*|\1${USRBINPATH}/${PYTHON_PN}|' \
		    ${D}${PTEST_PATH}/python/tests/Makefile
		grep -lrZ '#!/usr/bin/python' ${D}${PTEST_PATH}/python |
			xargs -0 sed -i -e 's|/usr/bin/python|${USRBINPATH}/${PYTHON_PN}|'
	fi
	#Remove build host references from various Makefiles
	find "${D}${PTEST_PATH}" -name Makefile -type f -exec \
	    sed -i \
	    -e 's,--sysroot=${STAGING_DIR_TARGET},,g' \
	    -e 's|${DEBUG_PREFIX_MAP}||g' \
	    -e 's:${HOSTTOOLS_DIR}/::g' \
	    -e 's:${RECIPE_SYSROOT_NATIVE}::g' \
	    -e 's:${RECIPE_SYSROOT}::g' \
	    -e 's:${BASE_WORKDIR}/${MULTIMACH_TARGET_SYS}::g' \
	    -e '/^RELDATE/d' \
	    {} +
}

do_install_append_class-native () {
	# Docs are not needed in the native case
	rm ${D}${datadir}/gtk-doc -rf
}

BBCLASSEXTEND = "native nativesdk"
