RRECOMMENDS:${PN}:append:intel-x86-common = "${@bb.utils.contains('ICXSDK', '1', ' intel-oneapi-toolkit-compiler intel-oneapi-toolkit-runtime ', '', d)}"
