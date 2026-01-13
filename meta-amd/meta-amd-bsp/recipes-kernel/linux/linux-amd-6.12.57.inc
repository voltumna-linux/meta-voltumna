FILESEXTRAPATHS:prepend := "${THISDIR}/linux-amd-6.12/linux-amd-6.12.57:"
SRCREV_meta = "2987fc4250f2ad7f6e2df663bba0742638fbae51"
SRCREV_machine = "8a243ecde1f6447b8e237f2c1c67c0bb67d16d67"

SRC_URI:append:siena := " \
           file://ntb.scc \
           file://ntb.cfg \
           file://amd_io.cfg \
           file://prof.scc \
           file://prof.cfg \
           file://misc.cfg \
	  "

SRC_URI:append:turin := " \
           file://ntb.scc \
           file://ntb.cfg \
           file://amd_io.cfg \
           file://prof.scc \
           file://prof.cfg \
           file://sdci.scc \
           file://sdci.cfg \
           file://misc.cfg \
	  "

SRC_URI:append:e2005 := " \
           file://amd_io.cfg \
           file://prof.cfg \
           file://prof.scc \
           file://gen_io.scc \
           file://asf.scc \
           file://i2c_slave.scc \
           file://misc.cfg \
          "

