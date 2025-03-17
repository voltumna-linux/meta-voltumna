#                                                                                
#     Makefile        External        25-JUL-2024               
#                                                                                
#     Copyright (C)  2006-2024  EPIX, Inc.  Released under GPL. 
#                                                                                
#     THIS IS A MACHINE GENERATED COPY                                           
#                                                                                
MAJVERSION := 5.x
TARGETARCH := x86_64


# invoked from the 2.6, 3.x, 4.x, 5.x, or 6.x kernel build system?
ifdef KERNELRELEASE
obj-m := pixci.o
pixci-objs := pixcipub.o pixcilnx.o
endif

# invoked from user or surrogate?
default:
ifeq "$(MAJVERSION)" "2.4"
	 gcc -O2 -minline-all-stringops -I/lib/modules/$(shell uname -r)/build/include -D__KERNEL__ -DMODULE -c pixcipub.c
	 ar -x pixcilnx_$(TARGETARCH)_5.13.a pixcilnx_5.13.o
	 ld -r -x -o pixci.o pixcipub.o pixcilnx_2.4.o
	 strip --strip-debug --discard-all pixci.o
	 mv pixci.o pixci_$(TARGETARCH).o
	 rm -f pixcipub.o
	 rm -f pixcilnx_5.13.o
endif
ifneq "" "$(filter $(MAJVERSION), 2.6 3.x 4.x 5.x 6.x )"
	 ar -x pixcilnx_$(TARGETARCH)_5.13.a pixcilnx_5.13.o
	 mv pixcilnx_5.13.o pixcilnx.o_shipped
	 touch .pixcilnx.o.cmd
ifneq "" "$(filter $(MAJVERSION),  5.x 6.x )"
	 $(MAKE) -C /home/alessio.bogani/build-images/ccd-2.y/build/tmp/work-shared/d-6244-x11dph-t-rnm/kernel-source M=$(shell pwd) modules
else
	 $(MAKE) -C /lib/modules/$(shell uname -r)/build SUBDIRS=$(shell pwd) modules
endif
	 strip --strip-debug --discard-all pixci.ko
	 mv pixci.ko pixci_$(TARGETARCH).ko
ifneq "" "$(filter $(TARGETARCH), i386 x86_64 )"
ifneq "" "$(filter $(MAJVERSION), 5.x 6.x )"
	 @ echo 'Note: Drivers built with a precompiled binary blob provide reduced mitigation against straight line speculation (SLS).'
endif
endif
	 - rm -f pixcilnx.o
	 - rm -f pixcilnx.o_shipped
	 - rm -f pixcipub.o
	 - rm -f pixci.o
	 - rm -f pixci.mod.o
	 - rm -f pixci.mod.c
	 - rm -f .pixci*
	 - rm -f .Module.symvers.cmd
	 - rm -f .modules.order.cmd
	 - rm -rf .tmp_versions
endif

clean:
	 - rm -f *.o
	 - rm -f *.ko
	 - rm -f pixcilnx.o_shipped
	 - rm -f .pixci*
	 - rm -f pixci.mod*
	 - rm -f .Module.symvers.cmd
	 - rm -f .modules.order.cmd
	 - rm -f modules.order
	 - rm -f Module.symvers
	 - rm -rf .tmp_versions
