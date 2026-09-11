HOMEPAGE = "https://github.com/theskumar/python-dotenv"
SUMMARY = "Python Dot Env Handler"
DESCRIPTION = "Shell Command and Library to write and read .env like files."
SECTION = "devel/python"
LICENSE = "BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE;md5=e914cdb773ae44a732b392532d88f072"

PYPI_PACKAGE = "python_dotenv"
UPSTREAM_CHECK_PYPI_PACKAGE = "${PYPI_PACKAGE}"

SRC_URI[sha256sum] = "a20a594dabeaa385725aa239d5244871c143ecb356add8a20fcf23773a6c3a35"

inherit pypi python_setuptools_build_meta

CVE_PRODUCT = "saurabh-kumar:python-dotenv theskumar:python-dotenv"
