require recipes-kernel/linux/linux-artesyn_6.12.bb

SRC_URI:append = " \
	file://preempt_rt.cfg \
        file://patch-6.12.79-rt17.patch \
	"
