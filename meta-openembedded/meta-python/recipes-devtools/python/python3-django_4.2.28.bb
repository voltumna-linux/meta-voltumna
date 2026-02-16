require python-django.inc
inherit python_setuptools_build_meta

SRC_URI += "file://0001-lower-setuptools-requirements.patch"
SRC_URI[sha256sum] = "a4b9cd881991add394cafa8bb3b11ad1742d1e1470ba99c3ef53dc540316ccfe"

RDEPENDS:${PN} += "\
    python3-sqlparse \
    python3-asgiref \
"

PYPI_PACKAGE = "django"

# Set DEFAULT_PREFERENCE so that the LTS version of django is built by
# default. To build the 4.x branch, 
# PREFERRED_VERSION_python3-django = "4.2.%" can be added to local.conf
DEFAULT_PREFERENCE = "-1"
