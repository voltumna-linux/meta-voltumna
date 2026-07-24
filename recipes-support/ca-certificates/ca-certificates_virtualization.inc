# Install Let's Encrypt intermediate certificates (E8/ECDSA, R11/RSA).
#
# Only active when 'virtualization' is in DISTRO_FEATURES.
#
# Some container registries (e.g., registry.yocto.io) don't send the
# full certificate chain. Go's TLS library (used by Docker, skopeo,
# podman) cannot verify the server certificate without the intermediate,
# even though the root CAs (ISRG Root X1/X2) are present.
#
# These intermediates are fetched at build time and installed alongside
# the standard CA certificates. update-ca-certificates (run in
# pkg_postinst) incorporates them into the system CA bundle.
#
# Source: https://letsencrypt.org/certificates/

SRC_URI += "https://letsencrypt.org/certs/2024/e8.pem;name=le-e8;unpack=0 \
            https://letsencrypt.org/certs/2024/r11.pem;name=le-r11;unpack=0"

SRC_URI[le-e8.sha256sum] = "f2c0dde62e2c90e6332fa55af79ed1a0c41329ad03ecf812bd89817a2fc340a9"
SRC_URI[le-r11.sha256sum] = "6c06a45850f93aa6e31f9388f956379d8b4fb7ffca5211b9bab4ad159bdfb7b9"

do_install:append () {
    for pem in ${UNPACKDIR}/e8.pem ${UNPACKDIR}/r11.pem; do
        if [ -f "$pem" ]; then
            install -d ${D}${datadir}/ca-certificates/letsencrypt
            # ca-certificates expects .crt extension
            base=$(basename "$pem" .pem)
            install -m 0644 "$pem" ${D}${datadir}/ca-certificates/letsencrypt/lets-encrypt-${base}.crt
        fi
    done

    # Add to ca-certificates.conf so update-ca-certificates includes them
    for crt in ${D}${datadir}/ca-certificates/letsencrypt/*.crt; do
        [ -f "$crt" ] || continue
        echo "letsencrypt/$(basename $crt)" >> ${D}${sysconfdir}/ca-certificates.conf
    done
}
