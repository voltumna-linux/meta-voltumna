
do_configure_append_mingw32 () {
		# don't try to build the other dtc components when installing libs
		sed -i 's/install-lib: all/install-lib: libfdt/g' ${S}/Makefile
}

do_compile_mingw32 () {
		oe_runmake libfdt
}

do_install_mingw32 () {
		oe_runmake install-lib install-includes
}

RDEPENDS_${PN}-misc_remove_mingw32 = "bash"

