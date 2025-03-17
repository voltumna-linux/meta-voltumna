FILESEXTRAPATHS_prepend := "${THISDIR}/files:"

SRC_URI_append_class-target += " \
	file://0099-tweak-MULTIARCH-for-powerpc-linux-gnuspe.patch \
	"
