SUMMARY = "Open-source IoT platform for data collection, processing, visualization, and device management"
DESCRIPTION = "\
The Thingsboard IoT Gateway is an open-source solution that allows you \
to integrate devices connected to legacy and third-party systems with Thingsboard."
HOMEPAGE = "https://thingsboard.io/"

LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

SRC_URI[sha256sum] = "5811a3c5a2334e41776f249df20c1d6a0def62a6e11e77bf2abeaa02f2725260"

inherit pypi setuptools3

PYPI_PACKAGE = "thingsboard-gateway"

RDEPENDS:${PN} += " python3-jsonpath-rw \
                    python3-regex \
                    python3-paho-mqtt \
                    python3-pyyaml \
                    python3-simplejson \
                    python3-requests \
                    python3-pip \
                    python3-pyrsistent \
                    python3-cachetools \
                    python3-orjson \
                    python3-psutil \
                    python3-pybase64 \
                    python3-grpcio \
                    python3-packaging \
                    python3-protobuf \
                    python3-service-identity \
                    python3-termcolor \
                    python3-charset-normalizer \
                    python3-mmh3 \
                    python3-dateutil \
                    python3-setuptools \
                    python3-urllib3 \
                    python3-questionary \
                    python3-pyfiglet \
                    python3-cryptography \
                    python3-pysocks \
"

SRC_URI += "file://thingsboard-gateway.service"

inherit systemd useradd

SYSTEMD_PACKAGES = "${PN}"
SYSTEMD_SERVICE:${PN} = "thingsboard-gateway.service"

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = " \
    --system --no-create-home \
    --comment 'ThingsBoard-Gateway Service' \
    --home-dir ${localstatedir}/lib/${BPN} \
    --shell ${base_sbindir}/nologin \
    --gid thingsboard_gateway thingsboard_gateway"
GROUPADD_PARAM:${PN} = "--system thingsboard_gateway"

FILES:${PN} += "/etc \
                /lib \
                /usr \
                ${localstatedir} \
"

do_install:append(){
    install -d ${D}${sysconfdir}/${BPN}/config
    install -m 0644 ${S}/thingsboard_gateway/config/*.json ${D}${sysconfdir}/${BPN}/config
    chown -R thingsboard_gateway:thingsboard_gateway ${D}${sysconfdir}/${BPN}

    install -d ${D}${systemd_system_unitdir}/
    install -m 0644 ${UNPACKDIR}/thingsboard-gateway.service ${D}${systemd_system_unitdir}/thingsboard-gateway.service

    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${sysconfdir}/tmpfiles.d
        echo "d ${localstatedir}/log/${BPN} 0755 thingsboard_gateway thingsboard_gateway -" \
            > ${D}${sysconfdir}/tmpfiles.d/${BPN}.conf
        echo "d ${localstatedir}/lib/${BPN} 0755 thingsboard_gateway thingsboard_gateway -" \
            >> ${D}${sysconfdir}/tmpfiles.d/${BPN}.conf
    fi
}
