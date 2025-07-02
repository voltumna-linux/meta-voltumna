SUMMARY = "A case-insensitive list for Python"
HOMEPAGE = "https://nocaselist.readthedocs.io/en/latest/"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://LICENSE;md5=86d3f3a95c324c9479bd8986968f4327"

SRC_URI[sha256sum] = "fb7306f5a3e045534e737ab7ecbeee039ba5e9bafbc5b5f231f616d7e9211b65"

inherit pypi python_setuptools_build_meta

DEPENDS += " \
	python3-setuptools-scm-native \
	python3-toml-native \
"

RDEPENDS:${PN} += " \
	python3-six \
"
