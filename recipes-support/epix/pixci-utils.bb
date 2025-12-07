DESCRIPTION = "Misc files for the PIXCI Frame Grabber Driver utils"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcb788c80a0384361b4de20420"
LICENSE = "MIT"

SRC_URI = " \
    file://90-pixci.rules \
    file://pixcimknod \
    "

FILES:${PN} += " \
        ${sbindir} \
	${sysconfdir}/udev/rules.d \
        "

do_install() {
    install -d ${D}${sysconfdir}/udev/rules.d/
    install -m 0644 ${WORKDIR}/90-pixci.rules ${D}${sysconfdir}/udev/rules.d/
    
    install -d ${D}${sbindir}
    install -m 0755 ${WORKDIR}/pixcimknod ${D}${sbindir}
}
