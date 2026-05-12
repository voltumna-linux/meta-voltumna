FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

PACKAGECONFIG = "opentelemetry_install otlp_api otlp_grpc otlp_http"

SRC_URI:append = " \
    file://enable-ppc32.patch \
    "

EXTRA_OECMAKE:append:ppce500v2 = "-DCMAKE_CXX_STANDARD_LIBRARIES=-latomic"
EXTRA_OECMAKE:append:ppc7400 = "-DCMAKE_CXX_STANDARD_LIBRARIES=-latomic"

# Under class-nativesdk, ${bindir} expands to ${SDKPATHNATIVE}/usr/bin, but the
# protobuf-native dependency stages protoc to recipe-sysroot-native/usr/bin.
# Use STAGING_BINDIR_NATIVE — class-invariant, matches grpc_1.80.0.bb.
EXTRA_OECMAKE:remove:class-nativesdk = "-DPROTOBUF_PROTOC_EXECUTABLE=${RECIPE_SYSROOT_NATIVE}${bindir}/protoc"
EXTRA_OECMAKE:append:class-nativesdk = " -DPROTOBUF_PROTOC_EXECUTABLE=${STAGING_BINDIR_NATIVE}/protoc"

BBCLASSEXTEND = "nativesdk"
