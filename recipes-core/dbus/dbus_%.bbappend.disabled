do_install:append:class-target() {
	sed -i 's,\/var\/run,\/run,g' \
               ${D}${nonarch_libdir}/tmpfiles.d/dbus.conf
}
