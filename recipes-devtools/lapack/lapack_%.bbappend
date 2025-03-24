PACKAGECONFIG:append = " lapacke"

BBCLASSEXTEND = "nativesdk"
INSANE_SKIP:${PN} += "buildpaths"
MACHINE_FEATURES:append = " highly-optimized"
