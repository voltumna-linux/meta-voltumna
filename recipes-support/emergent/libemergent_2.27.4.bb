include emergent.inc

do_compile[noexec] = "1"

RDEPENDS_${PN} = "tiff libavformat zlib gawk"

INSANE_SKIP_${PN} += "file-rdeps already-stripped"
INSANE_SKIP_${PN}-dev += "dev-elf ldflags file-rdeps"

do_install () {
	install -d ${D}${sbindir}
	install -m 0755 opt/EVT/myricom_mva/sbin/myri_create_devs ${D}${sbindir}

	install -d ${D}${includedir} ${D}${libdir}
	install -m 0755 opt/EVT/myricom_mva/lib/libmva.so ${D}${libdir}
	install -m 0644 opt/EVT/myricom_mva/include/mva*.h ${D}${includedir}

	install -m 0755 opt/EVT/eSDK/genicam/bin/Linux64_x64/lib*gcc48*.so ${D}${libdir}

	install -m 0755 opt/EVT/eSDK/lib/libEmergentCamera*.so.* ${D}${libdir}
	cp -P opt/EVT/eSDK/lib/libEmergentCamera*.so ${D}${libdir}
	cp opt/EVT/eSDK/lib/libEmergentG*.so ${D}${libdir}

	install -m 0644 opt/EVT/eSDK/include/*mergent*.h \
		opt/EVT/eSDK/include/EvtParamAttribute.h \
		opt/EVT/eSDK/include/GenTL.h \
		opt/EVT/eSDK/include/gigevisiondeviceinfo.h \
		opt/EVT/eSDK/include/networkinterfacecontroller.h \
		opt/EVT/eSDK/include/platformsymbols.h \
		${D}${includedir}
}

BBCLASSEXTEND = "native nativesdk"
