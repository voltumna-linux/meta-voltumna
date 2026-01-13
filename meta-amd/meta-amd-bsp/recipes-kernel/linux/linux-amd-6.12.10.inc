FILESEXTRAPATHS:prepend := "${THISDIR}/linux-amd-6.12/linux-amd-6.12.10:"
SRCREV_meta = "5d9c6c5b0531161f9e8e9d108740ebcec9177398"
SRCREV_machine = "a6ad5510dbb5f55cd2d1b44b11a18120bf79a5a3"

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

