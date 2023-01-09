FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
  
SRC_URI:append = " \
        file://fix-sigsys.patch \
        "
