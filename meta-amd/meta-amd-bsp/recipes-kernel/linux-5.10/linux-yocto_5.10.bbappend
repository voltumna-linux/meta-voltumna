require linux-yocto-common_5.10.inc

PR := "${INC_PR}.0"

KBRANCH:amd ?= "v5.10/standard/base"
SRCREV_machine:amd ?= "7abf3b31ec4e4fc9564b7a8db6844d9b4d71a1b2"

require linux-yocto-amdx86_5.10.inc
COMPATIBLE_MACHINE = "${MACHINE}"
