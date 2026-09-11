#
# Copyright (C) 2015 Wind River Systems, Inc.
#

require irqbalance.inc

SRCREV = "16844fb60368ddc8aaf7750ca44f67cacf99e1ad"
PV = "1.9.5+git"

SRC_URI = "git://github.com/Irqbalance/irqbalance;branch=master;protocol=https \
           file://add-initscript.patch \
           file://irqbalance-Add-status-and-reload-commands.patch \
          "

CFLAGS += "-Wno-error=format-security"
