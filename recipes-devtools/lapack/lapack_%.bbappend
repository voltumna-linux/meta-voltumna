PACKAGECONFIG:append = " lapacke"

BBCLASSEXTEND = "nativesdk"
MACHINE_FEATURES:remove = "qemu-usermode"
