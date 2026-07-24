#
# Copyright (C) 2015 Wind River Systems, Inc.
#

require irqbalance.inc

SRCREV = "cd9212f453db71bec2050c9236c4ce9f17e6d2b4"
PV = "1.9.5+git"

SRC_URI = "git://github.com/Irqbalance/irqbalance;branch=master;protocol=https \
           file://add-initscript.patch \
           file://irqbalance-Add-status-and-reload-commands.patch \
          "

CFLAGS += "-Wno-error=format-security"
