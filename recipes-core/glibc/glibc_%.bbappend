FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
        file://0001-Restore-PowerPC-SPE-e500-support.patch \
	"
