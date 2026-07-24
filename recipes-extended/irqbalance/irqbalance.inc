#
# Copyright (C) 2013 Wind River Systems, Inc.
#
SUMMARY = "IRQ allocation daemon"
DESCRIPTION = "A daemon to balance interrupts across multiple CPUs, \
which can lead to better performance and IO balance on SMP systems."

HOMEPAGE = "http://code.google.com/p/irqbalance/"
BUGTRACKER = "http://code.google.com/p/irqbalance/issues/list"

LICENSE = "GPL-2.0-only"
LIC_FILES_CHKSUM = "file://COPYING;md5=94d55d512a9ba36caa9b7df079bae19f \
		    file://irqbalance.c;beginline=6;endline=8;md5=b94e153694672307b503b1bc87dc9e24 \
		   "

DEPENDS = "glib-2.0"

INITSCRIPT_NAME = "irqbalanced"
INITSCRIPT_PARAMS = "defaults"

inherit autotools update-rc.d pkgconfig systemd

SYSTEMD_PACKAGES = "irqbalance"
SYSTEMD_SERVICE:irqbalance = "irqbalance.service"

EXTRA_OECONF = "--program-transform-name= \
	       "

# let the recipes or appends define options
#
PACKAGECONFIG ?= "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'systemd', '', d)}"
# enable,disable,depends,rdepends
#
PACKAGECONFIG[numa] = "--enable-numa,--disable-numa,numactl,"
PACKAGECONFIG[libcap-ng] = "--with-libcap-ng,--without-libcap-ng,libcap-ng,"
PACKAGECONFIG[systemd] = "--with-systemd --with-pkgconfdir=${sysconfdir},--with-pkgconfdir=${sysconfdir},systemd,"

do_install () {
        oe_runmake 'DESTDIR=${D}' install

	if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
		install -d ${D}${systemd_unitdir}/system
	else
		install -d ${D}${sysconfdir}/init.d
		cat ${S}/irqbalance.init | sed -e's,/usr/sbin,${sbindir},g' > ${D}${sysconfdir}/init.d/irqbalanced
		chmod 755 ${D}${sysconfdir}/init.d/irqbalanced
	fi
}

