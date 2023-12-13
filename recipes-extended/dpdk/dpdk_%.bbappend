PACKAGECONFIG_x11dph-t = " numa"
PACKAGECONFIG_06v45n = " numa"

FILES_${PN} += "${sysconfdir}/profile.d/dpdk.sh"

DEPENDS_class-target += "python3-pyelftools"
RDEPENDS_${PN}_class-target += "bash"
RDEPENDS_${PN}_class-nativesdk = "python3-core"

SRC_URI_append += " \
       file://reduce-queue-itr-interval-default-on-intel-nics.patch \
       "

do_configure_prepend () {
	# Enable HPET
	echo "CONFIG_RTE_LIBEAL_USE_HPET=y" >> ${S}/config/defconfig_${RTE_TARGET}
}

do_install () {
	oe_runmake O=${RTE_OUTPUT} T= install-runtime DESTDIR=${D}
#	oe_runmake O=${RTE_OUTPUT} T= install-kmod DESTDIR=${D} kerneldir=${MODULE_DIR}
	oe_runmake O=${RTE_OUTPUT} T= install-sdk DESTDIR=${D}

	# Install examples
	for dirname in ${S}/examples/*
	do
		install -m 0755 -d ${D}/${INSTALL_PATH}/examples/`basename ${dirname}`

		for appname in `find ${dirname} -regex ".*${EXAMPLES_BUILD_DIR}\/app\/[-0-9a-zA-Z0-9/_]*$"`
		do
			install -m 755 ${appname}	${D}/${INSTALL_PATH}/examples/`basename ${dirname}`/
		done
	done

	# Install test
	for dirname in ${S}/${TEST_DIR}/app/*
	do
		install -m 0755 -d ${D}/${INSTALL_PATH}/test

		for appname in `find ${dirname} -regex ".*test\/app\/[-0-9a-zA-Z0-9/_]*$"`
		do
			install -m 755 ${appname} ${D}/${INSTALL_PATH}/test
		done
	done

	cp -r ${S}/mk ${D}${INSTALL_PATH}/

	for ss in $(find ${D} -type f -name "*.py"); do
		sed -i -e "1s,#!.*python.*,#!${USRBINPATH}/env python3," ${ss}
	done
	
	install -d ${D}${sysconfdir}/profile.d
	cat <<-__EOF__ > ${D}${sysconfdir}/profile.d/dpdk.sh
	export RTE_SDK="${INSTALL_PATH}"
	__EOF__
}

BBCLASSEXTEND = "nativesdk"
MACHINE_FEATURES:remove = "qemu-usermode"
