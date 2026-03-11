require recipes-kernel/linux/linux-bb.org_6.6.bb

SRC_URI:append = " \
	file://preempt_rt_full.cfg \
	"
