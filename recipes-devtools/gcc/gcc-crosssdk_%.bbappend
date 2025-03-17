PACKAGECONFIG_CONFARGS ?= ""
EXTRA_OECONF_remove_mingw32 = "--enable-initfini-array --with-linker-hash-style=${LINKER_HASH_STYLE}"
EXTRA_OECONF_append_mingw32 = " --disable-initfini-array"
