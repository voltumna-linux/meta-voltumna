RDEPENDS:${PN} += "${@bb.utils.contains('ICXSDK', '1', ' intel-oneapi-toolkit-compiler intel-oneapi-toolkit-runtime ', '', d)}"
