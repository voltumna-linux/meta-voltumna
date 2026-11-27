DESCRIPTION = "Libbufferrt"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=e9f7e8627ac433ed277eab45950118e0"

SRC_URI = "https://gitlab.elettra.eu/cs/lib/libbufferrt/-/archive/${PV}/libbufferrt-${PV}.tar.bz2"
SRC_URI[sha256sum] = "afe68adc195d3e12c50b6e85ccf2aa47158b67a23520769ae7e137288f090b85"

# The tag list is only exposed as JSON by the GitLab API (the web UI needs a
# login), which the standard check cannot read: scrape the whole response
# through upstream-page-check.
inherit upstream-page-check
UPSTREAM_CHECK_URI = "https://gitlab.elettra.eu/api/v4/projects/cs%2Flib%2Flibbufferrt/repository/tags"
UPSTREAM_CHECK_REGEX = '"name":"(?P<pver>\d+(\.\d+)+)"'

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

BBCLASSEXTEND = "nativesdk"
