FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += " \
       file://60-drm-hotplug-mode.rules \
       file://hotplug-display-auto.sh \
       file://hotplug-display-mirrored.sh \
       file://hotplug-display-extended-h.sh \
       file://hotplug-display-extended-v.sh \
"
# Allowed options for MULTI_DISPLAY_MODE: auto | mirrored | extended-h | extended-v
MULTI_DISPLAY_MODE ?= "auto"

do_install:append() {
    sed -i 's/@MULTIDISPLAYMODE/${MULTI_DISPLAY_MODE}/' ${WORKDIR}/60-drm-hotplug-mode.rules

    install -d ${D}${sysconfdir}/udev/rules.d
    install -m 0644 ${WORKDIR}/60-drm-hotplug-mode.rules     ${D}${sysconfdir}/udev/rules.d/60-drm-hotplug-mode.rules

    install -d ${D}${sysconfdir}/udev/scripts/
    install -m 0755 ${WORKDIR}/hotplug-display-auto.sh ${D}${sysconfdir}/udev/scripts/hotplug-display-auto.sh
    install -m 0755 ${WORKDIR}/hotplug-display-mirrored.sh ${D}${sysconfdir}/udev/scripts/hotplug-display-mirrored.sh
    install -m 0755 ${WORKDIR}/hotplug-display-extended-h.sh ${D}${sysconfdir}/udev/scripts/hotplug-display-extended-h.sh
    install -m 0755 ${WORKDIR}/hotplug-display-extended-v.sh ${D}${sysconfdir}/udev/scripts/hotplug-display-extended-v.sh
}

RDEPENDS:${PN} += "${@bb.utils.contains('IMAGE_FEATURES', 'x11-base', 'xrandr', '', d)}"
