require recipes-kernel/linux/linux-bb.org_6.6.bb

SRC_URI:append = " \
	file://preempt_rt.cfg \
        file://patch-6.6.58-rt45.patch \
	"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${WORKDIR}/preempt_rt.cfg \
	${WORKDIR}/patch-6.6.58-rt45.patch \
        "
