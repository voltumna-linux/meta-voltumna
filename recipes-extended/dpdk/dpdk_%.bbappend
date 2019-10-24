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
}

