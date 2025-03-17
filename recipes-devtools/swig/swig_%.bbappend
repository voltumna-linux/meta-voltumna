# A wrapper script won't work to set SWIG_LIB for a mingw SDK. Instead, add an
# environment setup batch file to set SWIG_LIB when the SDK is configured.
do_install:append:class-nativesdk:mingw32() {
    install -d ${D}${SDKPATHNATIVE}/environment-setup.d

    cat <<HEREDOC > ${D}${SDKPATHNATIVE}/environment-setup.d/swig.bat
set SWIG_LIB=%OECORE_NATIVE_SYSROOT%\\usr\\share\\${BPN}\\${PV}
HEREDOC
}

FILES:${PN}:append:class-nativesdk:mingw32 = " ${SDKPATHNATIVE}/environment-setup.d"

