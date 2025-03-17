FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://dd_ibs_obs.cfg \
               file://gpt_disklabel.cfg \
		file://ip_route.cfg"
