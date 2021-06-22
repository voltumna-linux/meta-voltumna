do_install_append() {
    if [ "${libdir}" = "${nonarch_base_libdir}" ]; then
       mkdir -p ${D}/${nonarch_base_libdir}
       mv ${D}/lib/* ${D}/${nonarch_base_libdir}/
       rmdir ${D}/lib
    fi
}

FILES_${PN} = "${nonarch_base_libdir}/firmware/ti-connectivity/*"
