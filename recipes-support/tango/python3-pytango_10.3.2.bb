SUMMARY = "Tango for Python"
DESCRIPTION = "PyTango is a python module that exposes to Python the complete Tango C++ API"
HOMEPAGE = "https://pytango.readthedocs.io/"
LICENSE = "LGPL-3.0-only"
LIC_FILES_CHKSUM = "file://LICENSE.txt;md5=edf3c432b05ee3dda249e9c69af744f3"

DEFAULT_PREFERENCE = "-1"

DEPENDS += "\
	cpptango \
	${PYTHON_PN}-pybind11-native \
	${PYTHON_PN}-numpy-native \
	"

SRCREV = "886ffae73a39e6987514ddcaf378a1e074a1ddda"
SRC_URI = "\
	gitsm://gitlab.com/tango-controls/pytango.git;protocol=https;branch=stable \
	"
INSANE_SKIP:${PN} += "buildpaths already-stripped"

FILES:${PN} += " ${PYTHON_SITEPACKAGES_DIR}"

EXTRA_OECMAKE += "-DCMAKE_BUILD_TYPE=Release"

do_install:append() {
        rm -fr ${D}/*
	install -d ${D}${PYTHON_SITEPACKAGES_DIR}

	install -m 0644 ${S}/PyTango/__init__.py ${D}${PYTHON_SITEPACKAGES_DIR}/PyTango.py
	cp -r ${S}/tango ${D}${PYTHON_SITEPACKAGES_DIR}
	rm -fr ${D}${PYTHON_SITEPACKAGES_DIR}/tango/databaseds
        PYTHON_LIBVER="$(echo ${PYTHON_BASEVERSION} | sed 's/\([0-9]*\).\([0-9]*\)/\1\2/g')"
        install -m 0755 ${B}/_tango.cpython-${PYTHON_LIBVER}-${BUILD_SYS}-gnu.so \
		${D}${PYTHON_SITEPACKAGES_DIR}/tango/

	${PYTHON_PN} ${STAGING_LIBDIR}/${PYTHON_DIR}/py_compile.py ${D}${PYTHON_SITEPACKAGES_DIR}/PyTango.py
	${PYTHON_PN} ${STAGING_LIBDIR}/${PYTHON_DIR}/py_compile.py ${D}${PYTHON_SITEPACKAGES_DIR}/tango/*.py
}

RDEPENDS:${PN} += "\
    ${PYTHON_PN}-numpy \
    ${PYTHON_PN}-packaging \
    ${PYTHON_PN}-psutil \
    "

inherit pkgconfig cmake python3native python3targetconfig

BBCLASSEXTEND = "nativesdk"
