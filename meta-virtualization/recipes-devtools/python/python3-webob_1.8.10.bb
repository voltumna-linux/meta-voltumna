DESCRIPTION = "WSGI request and response object"
HOMEPAGE = "http://webob.org/"
SECTION = "devel/python"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://docs/license.txt;md5=8ed3584bcc78c16da363747ccabc5af5"

PYPI_PACKAGE = "webob"

SRC_URI[sha256sum] = "1c963a11f307bc3f624fbab9dde737701eae255f32981b7a5486a88db1767c2b"

inherit setuptools3 pypi

RDEPENDS:${PN} += " \
	python3-sphinx \
	"

