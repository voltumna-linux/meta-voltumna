
FILESEXTRAPATHS_prepend_mingw32 := "${THISDIR}/files:"
SRC_URI_append_mingw32 = " \
		file://configure.ac-Set-mym4_revision-to-0-if-not-a-git-rep.patch \
		"

