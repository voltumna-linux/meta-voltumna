FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

pkg_postinst:udev-hwdb:amd () {
}
pkg_postinst_ontarget:udev-hwdb:amd () {
    udevadm hwdb --update
}
