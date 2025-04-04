FILESEXTRAPATHS:prepend := "${THISDIR}/libpam:"

do_install:append() {
    sed -ie 's,\(.*pam_warn.*\),#\1,g' ${D}${sysconfdir}/pam.d/other
}

