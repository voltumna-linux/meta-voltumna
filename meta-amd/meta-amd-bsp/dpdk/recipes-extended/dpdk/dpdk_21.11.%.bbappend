FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

DEPENDS += "openssl"

RDEPENDS:dpdk-tools += "\
  python3-shell \
  python3-json \
  python3-pyelftools \
  python3-pprint \
  python3-debugger \
"

COMPATIBLE_MACHINE = "${MACHINE}"
DPDK_TARGET_MACHINE = "znver1"
