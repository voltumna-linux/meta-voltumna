####
#
#	Makefile for the Linux EDT driver
#
###

# target

# Get variables like DRIVERLIB, VER_SERIES, etc
ifeq ($(KERNELRELEASE),)
#Running normally (not KBUILD), so a simple include will do
include driver_rules.mk
else
#The makefile is being included by KBUILD from somewhere else, like /usr/src/linux.
#KBUILD_EXTMOD looks like install_dir/module in the kernel build system

CFLAGS_SAVE:=$(CFLAGS)

include $(KBUILD_EXTMOD)/driver_rules.mk

# Deal with Kernel version 2.6.24
#  As of 2.6.23, the kernel build will fail if CFLAGS is changed.
#
# Note that driver_rules.mk is used by the 2.4 kernel also, so to not
# break 2.4, driver_rules.mk still exports CFLAGS... we just copy those
# values to EXTRA_CFLAGS and restore the CFLAGS as set by the KBuild
# system.
EXTRA_CLFAGS += $(CFLAGS)
CFLAGS=$(CFLAGS_SAVE)

endif
# The kernel build system knows how to convert a .o_shipped to a .o,
# (by simply renaming).
# (The .a files exist anyway, for use with the 2.4 kernel module).
#NOTE: blob is the term used in the kbuild documentation.  Perhaps
# it means "Binary Library OBject"?
EDT_BLOB = $(DRIVERLIB:lib_%.a=%.o)


ifneq ($(strip $(CONFIG_PPC)),)
CPUTYPE=PPC
EXTRA_CFLAGS += -DBIG_ENDIAN
LDM= elf32ppc
else

ifneq ($(strip $(CONFIG_X86_64)),)

CPUTYPE=x86_64
LDM= elf_x86_64
else

CPUTYPE=
LDM= elf_i386
endif
endif

ifneq ($(strip $(CONFIG_ARM)),)
CPUTYPE=arm64
endif


ifneq ($(KERNELRELEASE),)
# 2.6 kbuild part of makefile

VPATH += ..

EXTRA_CFLAGS += -D_KERNEL -D__KERNEL__ -I$(SUBDIRS)/..  

#deal with remap_pfn/remap_page switch mid 2.6

REMAP_PFN_VERSION = $(shell grep remap_pfn /proc/kallsyms)

ifneq ($(REMAP_PFN_VERSION),)
EXTRA_CFLAGS += -DREMAP_PFN
endif

obj-m := edt.o
edt-y := edt_lnx_kernel.o edt_lnx_mm.o edt_mem_tag.o $(EDT_BLOB)

else


KDIR := /lib/modules/$(shell uname -r)/build

KTARGETDIR := /lib/modules/`uname -r`/kernel/drivers/misc
TARGET=../`uname -r`/edt.ko

default: build install

build: $(EDT_BLOB)
	$(MAKE) -C $(KDIR) M=$(shell pwd) V=1 SUBDIRS=$(CURDIR) 1>make.output
	mkdir -p ../`uname -r`
	cp edt.ko ../`uname -r`

modules_install:
	$(MAKE) -C $(KDIR) M=$(shell pwd) V=1 SUBDIRS=$(CURDIR) modules_install

# Create a .o_shipped object from the corresponding .a file.
$(EDT_BLOB): $(DRIVERLIB)
	@echo "making blob"
	ld -r -o $@ --whole-archive $(DRIVERLIB)
	# As of kernel 5.8.0, neccessary file for installation.
	touch .$@.cmd

.PHONY: install
install: build
	mkdir -p $(KTARGETDIR)
	install -c $(TARGET) $(KTARGETDIR)
	/sbin/depmod -a

.PHONY: uninstall
uninstall: objclean
	rm -f /lib/modules/`uname -r`/kernel/drivers/misc/edt.ko
	/sbin/depmod -a

.PHONY: load
load: default
	./edt_load

.PHONY: unload
unload:
	./edt_unload

.PHONY: objclean
objclean cleano:
	-rm -fr ../`uname -r`
	-rm -f *.o *.ko .*cmd *.o_shipped edt.mod.c Module.* make.output

endif

