require python-django.inc

inherit pypi setuptools3

SRC_URI += "file://0001-add-back-setuptools-support.patch"
SRC_URI[sha256sum] = "a4b9cd881991add394cafa8bb3b11ad1742d1e1470ba99c3ef53dc540316ccfe"

RDEPENDS:${PN} += "\
    ${PYTHON_PN}-sqlparse \
"

# PYPI package name changed from Django -> django
PYPI_PACKAGE = "django"

# Set DEFAULT_PREFERENCE so that the LTS version of django is built by
# default. To build the 4.x branch, 
# PREFERRED_VERSION_python3-django = "4.2.27" can be added to local.conf
DEFAULT_PREFERENCE = "-1"
