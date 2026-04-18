LINUX_VERSION = "6.18.2"
LINUX_VERSION_SUFFIX = "-lts"

LIC_FILES_CHKSUM = "file://COPYING;md5=6bc538ed5bd9a7fc9398086aedcd7e46"

SRCREV = "b2496f2fcb06db4d598d0073ad0e9e9be99b9288"

do_kernel_configcheck[noexec] = "1"

include linux-socfpga.inc
