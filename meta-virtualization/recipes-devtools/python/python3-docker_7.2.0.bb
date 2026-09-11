SUMMARY = "A Python library for the Docker Engine API."
HOMEPAGE = "https://github.com/docker/docker-py"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=34f3846f940453127309b920eeb89660"

SRC_URI[sha256sum] = "cebb93773d334f778e023a7ee352a8d6e13ab1bd3b863a4d4a59dec897df43ac"

DEPENDS += "python3-pip-native"
DEPENDS += "python3-setuptools-scm-native"
DEPENDS += "python3-hatch-vcs-native"

RDEPENDS:${PN} += " \
        python3-misc \
        python3-six \
        python3-docker-pycreds \
        python3-requests \
        python3-websocket-client \
	python3-packaging \
	python3-hatch-vcs \
"
inherit pypi python_hatchling
