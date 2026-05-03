FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-Port-PowerPC-SPE-e500-target-backend-to-GCC-13.4.patch \
    file://0001-Fix-SPE-vec_perm-ICE-with-memory-operands-in-vectori.patch \
    "
