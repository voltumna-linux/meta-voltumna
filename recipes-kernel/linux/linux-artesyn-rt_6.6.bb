require recipes-kernel/linux/linux-artesyn_6.6.bb

SRC_URI:append = " \
	file://preempt_rt.cfg \
        file://patch-6.6.129-rt70.patch \
	"
