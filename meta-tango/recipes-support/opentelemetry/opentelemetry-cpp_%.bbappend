FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

PACKAGECONFIG = "opentelemetry_install otlp_api otlp_grpc otlp_http"

SRC_URI:append = " \
    file://enable-ppc32.patch \
    "

EXTRA_OECMAKE:append:ppce500v2 = "-DCMAKE_CXX_STANDARD_LIBRARIES=-latomic"
EXTRA_OECMAKE:append:ppc7400 = "-DCMAKE_CXX_STANDARD_LIBRARIES=-latomic"

BBCLASSEXTEND = "nativesdk"
