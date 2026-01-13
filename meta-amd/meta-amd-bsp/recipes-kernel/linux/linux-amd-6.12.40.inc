FILESEXTRAPATHS:prepend := "${THISDIR}/linux-amd-6.12/linux-amd-6.12.40:"
SRCREV_meta = "52dd739a32215ffca801bc40daebee19a01b6f20"
SRCREV_machine = "d90ecb2b1308b3e362ec4c21ff7cf0a051b445df"

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

SRC_URI:append:e2005 := " \
           file://amd_io.cfg \
           file://prof.cfg \
           file://gen_io.scc \
           file://asf.scc \
           file://i2c_slave.scc \
          "

