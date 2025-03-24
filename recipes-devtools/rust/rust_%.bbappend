FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

SRC_URI:append = " \
	file://rust-setup.py \
	file://target-sde.json \
	file://target-sdk.json \
	"

do_install:append:class-target() {
	install -d ${D}${datadir}/post-relocate-setup.d
	install -m 0755 ${UNPACKDIR}/rust-setup.py ${D}${datadir}/post-relocate-setup.d/

	install -d ${D}${libdir}/rustlib/${RUST_HOST_SYS}
	install -m 0644 ${UNPACKDIR}/target-sde.json \
		${D}${libdir}/rustlib/${RUST_HOST_SYS}/${SDK_PREFIX}gnu.json
}

FILES:${PN}:append:class-target = " ${datadir}/post-relocate-setup.d"

do_install:append:class-nativesdk() {
	install -d ${D}${SDKPATHNATIVE}/post-relocate-setup.d
	install -m 0755 ${UNPACKDIR}/rust-setup.py ${D}${SDKPATHNATIVE}/post-relocate-setup.d/

	install -d ${D}${libdir}/rustlib/${SDK_PREFIX}gnu
	install -m 0644 ${UNPACKDIR}/target-sdk.json \
		${D}${libdir}/rustlib/${SDK_PREFIX}gnu/${SDK_PREFIX}gnu.json
}

FILES:${PN}:append:class-nativesdk = " ${SDKPATHNATIVE}/post-relocate-setup.d"
