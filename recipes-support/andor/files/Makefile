#
#	Driver-level BitFlow makefile for bitflow.ko
#
#	Supports building bitflow.ko for custom kernels.
#
#	Kernel 2.6.24 specific variable assignment; see CFLAGS_EXTRA
#
###
#
#	$Author: steve $
#
#	$Date: 2020/11/11 23:36:03 $
#
#	$Id: Makefile_dist,v 1.6 2020/11/11 23:36:03 steve Exp $
#
###
#
BF_LIB = ../64b/lib
#
###
#
bitflow-objs := bflki.o $(BF_LIB)/libBFmodule.o

obj-m := bitflow.o
#
#	Before 2.6.24 this was just called CFLAGS 
#
EXTRA_CFLAGS +=	\
			-D __BF_VERSION__=$(VERSION) \
			-D __BF_PATCHLEVEL__=$(PATCHLEVEL) \
			-D __BF_SUBLEVEL__=$(SUBLEVEL) \
			-D __BF_EXTRAVERSION__=$(EXTRAVERSION)
#
###
#
#	Enable basic optimizing.
#
#EXTRA_CFLAGS += -O

SRC := $(shell pwd)
all:
	$(MAKE) -C $(KERNEL_SRC) M=$(SRC)

ifeq	($(BF_MAKE_BITFLOW),yes)
EXTRA_CFLAGS	+= -D BF_MAKE_BITFLOW=yes
endif
#
###
#
#	$Log: Makefile_dist,v $
#	Revision 1.6  2020/11/11 23:36:03  steve
#	No optimization by default.
#
#	Revision 1.5  2020/10/08 01:41:28  steve
#	We're going to enable basic optimization.
#
#	Revision 1.4  2019/04/09 22:00:53  steve
#	It would appear that linking a kernel module against an archive file is not officially supported, and from kernel version 4.20+, linking fails, because libBFmodule.a is not found. This is easily fixed, by renmaing libBFmodule.a to libBFmodule.o_shipped, and changing all refereces to libBFmodule.o, which appears to be the officially supported naming scheme.
#
#	Revision 1.3  2008/11/26 14:19:31  steve
#	Final tweak on build switches
#
#	Revision 1.2  2008-10-08 18:13:33  steve
#	Release test ready.
#
#	Revision 1.1  2008-09-29 19:13:44  steve
#	Now have 32b/64b kernel lib, dist Makefiles.
#
#
