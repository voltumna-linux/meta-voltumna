inherit python3native python3-dir python3targetconfig

export STAGING_INCDIR
export STAGING_LIBDIR
export BUILD_SYS 
export HOST_SYS

RDEPENDS:${PN}-python += "python3"
PACKAGECONFIG_${PN}-python[xen] = ",,,xen-python"

PACKAGES += "${PN}-python-staticdev ${PN}-python-dev ${PN}-python-dbg ${PN}-python"

FILES:${PN}-python-staticdev += "${PYTHON_SITEPACKAGES_DIR}/*.a"
FILES:${PN}-python-dev += "${PYTHON_SITEPACKAGES_DIR}/*.la"
FILES:${PN}-python-dbg += "${PYTHON_SITEPACKAGES_DIR}/.debug/"
FILES:${PN}-python = "${bindir}/* ${libdir}/* ${libdir}/${PYTHON_DIR}/*"

# Currently the libvirt-python debug libraries contain buildpaths
INSANE_SKIP:${PN}-dbg += "buildpaths"

SRC_URI += "http://libvirt.org/sources/python/${LIBVIRT_PYTHON_ARCHIVE_NAME}.tar.gz;name=libvirt_python;subdir=${BP}"
LIBVIRT_PYTHON_ARCHIVE_NAME = "${BPN}_python-${LIBVIRT_VERSION}"
SRC_URI[libvirt_python.sha256sum] = "2cc02c0b91a9abd140185feab46b33281091d4deffbc1bbfdb68ce682359f2b0"

export LIBVIRT_API_PATH = "${S}/docs/libvirt-api.xml"
export LIBVIRT_CFLAGS = "-I${S}/include"
export LIBVIRT_LIBS = "-L${B}/src/.libs -lvirt -ldl"
export LDFLAGS = "-L${B}/src/.libs"

LIBVIRT_INSTALL_ARGS = "--root=${D} \
    --prefix=${prefix} \
    --install-lib=${PYTHON_SITEPACKAGES_DIR} \
    --install-data=${datadir}"

python __anonymous () {
    pkgconfig = d.getVar('PACKAGECONFIG')
    if ('python') in pkgconfig.split():
        d.setVar('LIBVIRT_PYTHON_ENABLE', '1')
    else:
        d.setVar('LIBVIRT_PYTHON_ENABLE', '0')
}

do_compile:append() {
	if [ "${LIBVIRT_PYTHON_ENABLE}" = "1" ]; then
		# we need the python bindings to look into our source dir, not
		# the syroot staged pkgconfig entries. So we clear the sysroot
		# for just this portion.
		export PKG_CONFIG_SYSROOT_DIR=
		src=${UNPACKDIR}/${BP}/${LIBVIRT_PYTHON_ARCHIVE_NAME}
		if [ ! -d $src ]; then
			bbfatal "Python source not found at expected location \"$src\". Please check that this task logic and SRC_URI are consistent."
		fi
		cd $src
		${STAGING_BINDIR_NATIVE}/python3-native/python3 setup.py build
		cd -
	fi
}

do_install:append() {
	if [ "${LIBVIRT_PYTHON_ENABLE}" = "1" ]; then
		# we need the python bindings to look into our source dir, not
		# the syroot staged pkgconfig entries. So we clear the sysroot
		# for just this portion.
		export PKG_CONFIG_SYSROOT_DIR=
		src=${UNPACKDIR}/${BP}/${LIBVIRT_PYTHON_ARCHIVE_NAME}
		if [ ! -d $src ]; then
			bbfatal "Python source not found at expected location \"$src\". Please check that this task logic and SRC_URI are consistent."
		fi
		cd $src
		${STAGING_BINDIR_NATIVE}/python3-native/python3 setup.py install \
			--install-lib=${D}/${PYTHON_SITEPACKAGES_DIR} ${LIBVIRT_INSTALL_ARGS}
		cd -
	fi
}
