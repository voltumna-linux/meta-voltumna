require recipes-kernel/linux/linux-bb.org_5.10.bb

SRC_URI:append = " \
	file://preempt_rt.cfg \
	file://patch-5.10.165-rt81.patch \
	"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${WORKDIR}/preempt_rt.cfg \
	${WORKDIR}/patch-5.10.165-rt81.patch \
        "
