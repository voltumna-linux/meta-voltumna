FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

PACKAGECONFIG:append =" efi"

pkg_postinst:udev-hwdb:amd () {
}
pkg_postinst_ontarget:udev-hwdb:amd () {
    udevadm hwdb --update
}
