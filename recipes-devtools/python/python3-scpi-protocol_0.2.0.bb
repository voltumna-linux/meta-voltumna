SUMMARY = "Sans I/O python SCPI parser library"
HOMEPAGE = "https://gitlab.com/tiagocoutinho/scpi-protocol/"
LICENSE = "GPLv3"
LIC_FILES_CHKSUM = "file://setup.py;md5=7d55b0255ec50fa026cf2633286e2d9b"

SRC_URI[sha256sum] = "8389b441119754e23d70500be0e587ab8993d7462ca95fd4d6f466699c54251c"

inherit pypi setuptools3 ptest

RDEPENDS_${PN} += "\
    ${PYTHON_PN}-numpy \
    "

BBCLASSEXTEND = "native nativesdk"

