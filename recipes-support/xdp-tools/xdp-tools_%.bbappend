do_install:append:class-nativesdk () {
	rm -fr "${D}${prefix}/sbin"
}

BBCLASSEXTEND = "nativesdk"
