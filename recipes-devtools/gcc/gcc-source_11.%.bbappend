FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
    file://0001-Revert-Delete-powerpcspe-to-reintegrate-SPE-architec.patch \
    file://0002-expr-Use-memory-path-for-PARALLEL-group-load-store-w.patch \
    file://0003-powerpcspe-Fix-E500-calling-convention-for-DFmode-TF.patch \
    "
