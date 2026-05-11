require recipes-kernel/linux/linux-bb.org_6.12.bb

SRC_URI:append = " \
	file://preempt_rt.cfg \
        file://patch-6.12.39-rt11.patch \
	"

KERNEL_CONFIG_FRAGMENTS:append = " \
	${WORKDIR}/preempt_rt.cfg \
	${WORKDIR}/patch-6.12.39-rt11.patch \
        "
