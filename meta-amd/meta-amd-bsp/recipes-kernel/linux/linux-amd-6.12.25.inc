FILESEXTRAPATHS:prepend := "${THISDIR}/linux-amd-6.12/linux-amd-6.12.25:"
SRCREV_meta = "1f6ab68a1d86836bf1b82b791df03da3cfeacb3f"
SRCREV_machine = "ef4999852d307d38cfdecd91ed6892cc03beb9b8"

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
           file://cxl.scc \
	  "

