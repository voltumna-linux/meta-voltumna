DESCRIPTION = "Library for Gussian fitting"
LICENSE = "GPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE;md5=6f9f2aecf846d428f2b35d46d9c5ebe2"

DEPENDS:append = "gsl openblas"

SRC_URI = "https://gitlab.elettra.eu/cs/lib/libfit/-/archive/${PV}/libfit-${PV}.tar.bz2"
SRC_URI[sha256sum] = "2b279235c1e1de02e10a650336bb6c2bab5d013c31f79380af57cfbd2c767924"

# The tag list is only exposed as JSON by the GitLab API (the web UI needs a
# login), which the standard check cannot read: scrape the whole response
# through upstream-page-check. The closing quote of the regex keeps suffixed
# tags like 3.0.1a out of the comparison.
inherit upstream-page-check
UPSTREAM_CHECK_URI = "https://gitlab.elettra.eu/api/v4/projects/cs%2Flib%2Flibfit/repository/tags"
UPSTREAM_CHECK_REGEX = '"name":"(?P<pver>\d+(\.\d+)+)"'

do_install() {
	oe_runmake PREFIX=${D}${prefix} install
}

PARALLEL_MAKE = ""

BBCLASSEXTEND = "nativesdk"
