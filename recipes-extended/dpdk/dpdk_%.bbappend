RDEPENDS:${PN}:class-nativesdk += "python3-core"
DEPENDS:class-nativesdk = "python3-pyelftools-native"

SRC_URI:append:d-e5462-x7dwu = " \
	file://0001-Remove-SSE4.2-code.patch \
	"

BBCLASSEXTEND = "native nativesdk"
