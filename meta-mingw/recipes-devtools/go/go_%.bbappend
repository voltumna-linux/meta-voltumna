do_install:append:class-nativesdk:mingw32() {
    install -d ${D}${SDKPATHNATIVE}/environment-setup.d

    cat <<EOF > ${D}${SDKPATHNATIVE}/environment-setup.d/go.bat
set GOROOT=%OECORE_NATIVE_SYSROOT%\\usr\\lib\\${BPN}
EOF
}

FILES:${PN}:append:class-nativesdk:mingw32 = " ${SDKPATHNATIVE}/environment-setup.d"
