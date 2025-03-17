require recipes-kernel/linux/linux-artesyn_5.4.bb

SRC_URI_append += " \
	file://preempt_rt_full.cfg \
	file://patch-5.4.193-rt74.patch \
	"
