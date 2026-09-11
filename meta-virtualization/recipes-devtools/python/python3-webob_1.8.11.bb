DESCRIPTION = "WSGI request and response object"
HOMEPAGE = "http://webob.org/"
SECTION = "devel/python"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://docs/license.txt;md5=8ed3584bcc78c16da363747ccabc5af5"

PYPI_PACKAGE = "webob"

SRC_URI[sha256sum] = "aa8c27231070b135c025e567a9cd7eda03f4df71352ffaac740cb6a75f0f81a5"

CVE_PRODUCT = "pylons:webob pylonsproject:webob"

inherit setuptools3 pypi

RDEPENDS:${PN} += " \
	python3-sphinx \
	"

