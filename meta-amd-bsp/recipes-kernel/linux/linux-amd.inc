
FILESEXTRAPATHS:prepend := "${THISDIR}/linux-amd:"

SRC_URI:append:v3000 := " \
           file://xgbe.cfg \
           file://amd_io.cfg \
           file://v3000-edac.scc \
           file://v3000-eSPI.scc \
           file://spi.scc \
	  "

SRC_URI:append:siena := " \
           file://ntb.scc \
           file://ntb.cfg \
           file://amd_io.cfg \
	   file://prof.scc \
	   file://prof.cfg \
	  "

SRC_URI:append:turin := " \
           file://ntb.scc \
           file://ntb.cfg \
           file://amd_io.cfg \
	   file://prof.scc \
	   file://prof.cfg \
	   file://sdci.scc \
	   file://sdci.cfg \
	  "

