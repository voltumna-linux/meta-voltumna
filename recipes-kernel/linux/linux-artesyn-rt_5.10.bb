require recipes-kernel/linux/linux-artesyn_5.10.bb

SRC_URI:append = " \
	file://preempt_rt_full.cfg \
	file://patch-5.10.165-rt81.patch \
	"
