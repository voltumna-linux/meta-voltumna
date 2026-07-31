FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:remove = "file://0001-Assume-f2py-being-the-same-version-as-numpy.patch"
SRC_URI:append = " file://0001-Assume-f2py-being-the-same-version-as-numpy_updated.patch"

INSANE_SKIP:${PN} += "buildpaths"
