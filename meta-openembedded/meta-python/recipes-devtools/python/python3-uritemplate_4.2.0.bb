# This recipe is originally from meta-openstack:
# https://git.yoctoproject.org/cgit/cgit.cgi/meta-cloud-services/tree/meta-openstack/recipes-devtools/python/python3-uritemplate_3.0.0.bb?h=master

SUMMARY = "Simple python library to deal with URI Templates."
LICENSE = "Apache-2.0 | BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=0f6d769bdcfacac3c1a1ffa568937fe0"

SRC_URI[sha256sum] = "480c2ed180878955863323eea31b0ede668795de182617fef9c6ca09e6ec9d0e"

inherit pypi setuptools3 ptest-python-pytest

BBCLASSEXTEND = "native nativesdk"
