SUMMARY = "HTTP/2 C Library and tools"
HOMEPAGE = "https://nghttp2.org/"
SECTION = "libs"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://COPYING;md5=764abdf30b2eadd37ce47dcbce0ea1ec"

UPSTREAM_CHECK_URI = "https://github.com/nghttp2/nghttp2/releases"

SRC_URI = "\
    https://github.com/nghttp2/nghttp2/releases/download/v${PV}/nghttp2-${PV}.tar.xz \
    file://0001-fetch-ocsp-response-use-python3.patch \
    file://CVE-2023-35945.patch \
    file://CVE-2023-44487.patch \
    file://CVE-2024-28182-0001.patch \
    file://CVE-2024-28182-0002.patch \
"
SRC_URI[sha256sum] = "68271951324554c34501b85190f22f2221056db69f493afc3bbac8e7be21e7cc"

inherit cmake manpages python3native
PACKAGECONFIG[manpages] = ""

# examples are never installed, and don't need to be built in the
# first place
EXTRA_OECMAKE = "-DENABLE_EXAMPLES=OFF -DENABLE_APP=OFF -DENABLE_HPACK_TOOLS=OFF"

# Do not let configure try to decide this.
#
EXTRA_OECMAKE += "-DENABLE_PYTHON_BINDINGS=OFF"

PACKAGES =+ "lib${BPN} ${PN}-proxy "

RDEPENDS:${PN} = "${PN}-proxy (>= ${PV})"
RDEPENDS:${PN}:class-native = ""
RDEPENDS:${PN}-proxy = "openssl python3-core python3-io python3-shell"

ALLOW_EMPTY:${PN} = "1"
FILES:${PN} = ""
FILES:lib${BPN} = "${libdir}/*${SOLIBS}"
FILES:${PN}-proxy = "${bindir}/nghttpx ${datadir}/${BPN}/fetch-ocsp-response"

BBCLASSEXTEND = "native nativesdk"
