HOMEPAGE = "http://www.newrelic.com"
SUMMARY = "New Relic Python Agent"
DESCRIPTION = "\
  Python agent for the New Relic web application performance monitoring \
  service. Check the release notes for what has changed in this version. \
  "
SECTION = "devel/python"
LICENSE = "BSD-2-Clause AND BSD-3-Clause AND MIT AND Python-2.0 AND LicenseRef-NewRelic"
LIC_FILES_CHKSUM = "file://LICENSE;md5=2b42edef8fa55315f34f2370b4715ca9"

# NewRelic is a custom, non-SPDX license identifier -- OE-core's SPDX-2
# validator remaps it to LicenseRef-NewRelic on parse. Point the resolver at
# the top-level LICENSE file that already covers this content. Note: the
# NO_GENERIC_LICENSE varflag KEY drops the "LicenseRef-" prefix (per the
# spdx_license.LicenseRef regex in oe.license).
NO_GENERIC_LICENSE[NewRelic] = "LICENSE"

SRC_URI[sha256sum] = "f9443060aa32f95f2db443545ba8b15350be2d66ec22fadcdcda11f5472a06f6"

inherit pypi python_setuptools_build_meta

DEPENDS += "python3-setuptools-scm-native"

# Upstream pyproject.toml pins setuptools_scm<10 (line 61) but oe-core ships
# 10.0.5, so the PEP 517 build-meta backend's requirement check rejects the
# available version with "Missing dependencies: setuptools_scm<10,>=6.4".
# Relax the upper bound in-place; the v10 release was non-breaking for the
# setuptools_scm features newrelic actually uses (just version derivation
# from git tags via [tool.setuptools_scm] in the same file).
do_configure:prepend() {
    sed -i 's|"setuptools_scm>=6.4,<10"|"setuptools_scm>=6.4"|g' ${S}/pyproject.toml ${S}/setup.py
}

FILES:${PN}-dbg += "\
  ${PYTHON_SITEPACKAGES_DIR}/newrelic-${PV}/newrelic/*/.debug \
  ${PYTHON_SITEPACKAGES_DIR}/newrelic-${PV}/newrelic/packages/*/.debug/ \
  "

# The opentelemetry_proto vendored submodule (new in 13.x) ships a
# generate_pb2.sh dev helper that regenerates the protobuf python bindings
# from the .proto files. It has a bash shebang and is not used at runtime —
# only by maintainers when refreshing the bundled pb2.py outputs. Shipping
# it pulls bash into RDEPENDS (do_package_qa [file-rdeps] catches the
# /bin/bash shebang) for no runtime benefit; drop it from the install.
do_install:append() {
    rm -f ${D}${PYTHON_SITEPACKAGES_DIR}/newrelic/packages/opentelemetry_proto/generate_pb2.sh
}
