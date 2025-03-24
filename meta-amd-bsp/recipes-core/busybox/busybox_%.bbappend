FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI:append:amd = " \
	    file://gpt_disklabel.cfg \
           "
