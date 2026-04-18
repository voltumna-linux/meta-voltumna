# Settings for ubifs
MKUBIFS_ARGS ?= "--leb-size 1032192 --min-io-size 8192 --max-leb-cnt 8600"
UBINIZE_ARGS ?= "--peb-size 1024KiB --min-io-size 8192 --sub-page-size 8192"
MULTIUBI_BUILD += "nand"
MKUBIFS_ARGS_nand ?= "--leb-size 1032192 --min-io-size 8192 --max-leb-cnt 8600"
UBINIZE_ARGS_nand ?= "--peb-size 1024KiB --min-io-size 8192 --sub-page-size 8192"
MULTIUBI_BUILD += "nor"
MKUBIFS_ARGS_nor ?= "-F -e 65408 -m 1 -c 8600"
UBINIZE_ARGS_nor ?= "-p 65536 -m 1 -s 1"

