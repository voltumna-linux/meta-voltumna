require linux-yocto-common_5.10.inc

PR := "${INC_PR}.0"

KBRANCH:amd ?= "v5.10/standard/preempt-rt/base"
SRCREV_machine:amd ?= "2d7a731e45ade04ee2f2714f189c7c98e00b2238"

require linux-yocto-amdx86_5.10.inc
COMPATIBLE_MACHINE = "${MACHINE}"
