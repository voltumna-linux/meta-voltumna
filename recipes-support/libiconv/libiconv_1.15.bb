SUMMARY = "Character encoding support library"
DESCRIPTION = "GNU libiconv - libiconv is for you if your application needs to support \
multiple character encodings, but that support lacks from your system."
HOMEPAGE = "http://www.gnu.org/software/libiconv"
SECTION = "libs"
NOTES = "Needs to be stripped down to: ascii iso8859-1 eucjp iso-2022jp gb utf8"
PROVIDES = "virtual/libiconv"
PR = "r1"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://COPYING.LIB;md5=9f604d8a4f8e74f4f5140845a21b6674 \
                    file://libcharset/COPYING.LIB;md5=9f604d8a4f8e74f4f5140845a21b6674"

SRC_URI = "${GNU_MIRROR}/${BPN}/${BPN}-${PV}.tar.gz"

SRC_URI[md5sum] = "ace8b5f2db42f7b3b3057585e80d9808"
SRC_URI[sha256sum] = "ccf536620a45458d26ba83887a983b96827001e92a13847b45e4925cc8913178"

S = "${WORKDIR}/libiconv-${PV}"

inherit autotools pkgconfig gettext

# Need to use absolute paths as autoreconf will recurse into libchardet
EXTRA_AUTORECONF += "-I ${S}/m4 -I ${S}/srcm4"

python __anonymous() {
    if d.getVar("TARGET_OS") != "linux":
        return
    if d.getVar("TCLIBC") == "glibc":
        raise bb.parse.SkipPackage("libiconv is provided for use with uClibc only - glibc already provides iconv")
}

EXTRA_OECONF += "--enable-shared --enable-static --enable-relocatable"

LEAD_SONAME = "libiconv.so"

do_configure:prepend () {
	rm -f ${S}/m4/libtool.m4 ${S}/m4/ltoptions.m4 ${S}/m4/ltsugar.m4 ${S}/m4/ltversion.m4 ${S}/m4/lt~obsolete.m4 ${S}/libcharset/m4/libtool.m4 ${S}/libcharset/m4/ltoptions.m4 ${S}/libcharset/m4/ltsugar.m4 ${S}/libcharset/m4/ltversion.m4 ${S}/libcharset/m4/lt~obsolete.m4
}

do_configure:append () {
        # forcibly remove RPATH from libtool
        sed -i 's|^hardcode_libdir_flag_spec=.*|hardcode_libdir_flag_spec=""|g' *libtool
        sed -i 's|^runpath_var=LD_RUN_PATH|runpath_var=_NO_RPATH_|g' *libtool
}

do_install:append () {
	rm -rf ${D}${libdir}/preloadable_libiconv.so
	rm -rf ${D}${libdir}/charset.alias
}

BBCLASSEXTEND = "nativesdk"
