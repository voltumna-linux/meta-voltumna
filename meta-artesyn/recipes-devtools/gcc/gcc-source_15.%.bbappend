FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-Port-PowerPC-SPE-e500-target-backend-to-GCC-13.4.patch \
    file://0002-Fix-SPE-vec_perm-ICE-with-memory-operands-in-vectori.patch \
    file://0003-Adapt-powerpcspe-backend-to-GCC-15-API-changes.patch \
    file://0004-powerpcspe-modernize-VECTOR_TYPE_P-and-by-pieces-mov.patch \
    file://0005-powerpcspe-fix-split2-segfault-on-TFmode-MEM-stores-.patch \
    file://0006-recog-don-t-gcc_unreachable-in-apply_to_rvalue_1-s-a.patch \
    "
