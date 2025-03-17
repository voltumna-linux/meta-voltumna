PACKAGECONFIG_CONFARGS ?= ""
EXTRA_OECONF:remove:mingw32 = "--enable-initfini-array --with-linker-hash-style=${LINKER_HASH_STYLE}"
EXTRA_OECONF:append:mingw32 = " --disable-initfini-array"
