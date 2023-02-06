RDEPENDS:${PN}:class-nativesdk += "python3-core"
DEPENDS:class-nativesdk = "python3-pyelftools-native"

BBCLASSEXTEND = "native nativesdk"
