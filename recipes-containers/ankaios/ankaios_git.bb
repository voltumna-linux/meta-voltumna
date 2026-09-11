SUMMARY = "Eclipse Ankaios: Lightweight container orchestrator for embedded Linux"
DESCRIPTION = "Eclipse Ankaios is a lightweight container/workload orchestrator for embedded Linux systems. This recipe builds Ankaios from source using vendored Rust crates."
HOMEPAGE = "https://eclipse-ankaios.github.io/ankaios/latest/"
BUGTRACKER = "https://github.com/eclipse-ankaios/ankaios/issues"

SECTION = "virtualization/tools"

CVE_PRODUCT = "eclipse:ankaios"

# Ankaios itself is Apache-2.0; the rest is the license union of the >700 vendored
# crates, derived from upstream deny.toml (release-1.0) and verified against
# ankaios-crates.inc (ring->OpenSSL, foldhash->Zlib, borrow-or-share->MIT-0,
# unicode-ident->Unicode-3.0).
LICENSE = "Apache-2.0 AND BSD-3-Clause AND ISC AND MIT AND MIT-0 AND OpenSSL AND Unicode-3.0 AND Zlib"
LIC_FILES_CHKSUM = "file://LICENSE;md5=3b83ef96387f14655fc854ddc3c6bd57"

# Container runtime stack is not supported on MIPS
COMPATIBLE_HOST = "^(?!(qemu)?mips).*"

# Build dependencies
DEPENDS += "protobuf-native"

PV = "1.0.1+git"

SRC_URI = "\
    git://github.com/eclipse-ankaios/ankaios.git;protocol=https;branch=release-1.0 \
    file://state.yaml \
    file://ank.conf \
    file://ank-server.conf \
    file://ank-agent.conf \
    file://ank-server.service \
    file://ank-agent.service \
    file://ank-server;subdir=init-scripts \
    file://ank-agent;subdir=init-scripts \
    file://ank-server.default \
    file://ank-agent.default \
"

# v1.0.1 tag commit
# When bumping SRCREV, re-diff upstream deny.toml and re-check LICENSE against the crate graph.
SRCREV = "cde70616706b58fd03e4de3f7423addaffa58720"

# cargo-update-recipe-crates provides the `update_crates` task used to
# regenerate ankaios-crates.inc after an SRCREV bump.
inherit cargo cargo-update-recipe-crates systemd update-rc.d

require ${BPN}-crates.inc

# Package split:
# - ank-server: server binary + server config + systemd unit
# - ank-agent: agent binary + agent config + systemd unit
# - ank: CLI binary ("ank")
# - ankaios (${PN}): meta package pulling server+agent+cli
PACKAGE_BEFORE_PN = "ank ank-agent ank-server"

ALLOW_EMPTY:${PN} = "1"

FILES:ank += "${bindir}/ank \
    ${sysconfdir}/ankaios/ank.conf \
"

FILES:ank-agent += "\
    ${bindir}/ank-agent \
    ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', '${systemd_system_unitdir}/ank-agent.service', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', '${sysconfdir}/init.d/ank-agent', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', '${sysconfdir}/default/ank-agent', '', d)} \
    ${sysconfdir}/ankaios/ank-agent.conf \
"

FILES:ank-server += "\
    ${bindir}/ank-server \
    ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', '${systemd_system_unitdir}/ank-server.service', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', '${sysconfdir}/init.d/ank-server', '', d)} \
    ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', '${sysconfdir}/default/ank-server', '', d)} \
    ${sysconfdir}/ankaios/state.yaml \
    ${sysconfdir}/ankaios/ank-server.conf \
"

RDEPENDS:${PN} = "ank ank-agent ank-server"

# The agent shells out to a container runtime to launch workloads
# Ankaios does not require the following to start, but running workloads requires Podman and/or containerd + nerdctl.
RRECOMMENDS:ank-agent += "podman \
                          containerd \
                          nerdctl \
                          "

CONFFILES:ank = "${sysconfdir}/ankaios/ank.conf"
CONFFILES:ank-server = "${sysconfdir}/ankaios/state.yaml ${sysconfdir}/ankaios/ank-server.conf ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', '${sysconfdir}/default/ank-server', '', d)}"
CONFFILES:ank-agent = "${sysconfdir}/ankaios/ank-agent.conf ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', '${sysconfdir}/default/ank-agent', '', d)}"

# Install/enable systemd units when systemd is enabled
SYSTEMD_PACKAGES = "${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'ank-server ank-agent', '', d)}"
SYSTEMD_SERVICE:ank-server = "ank-server.service"
SYSTEMD_SERVICE:ank-agent = "ank-agent.service"
SYSTEMD_AUTO_ENABLE:ank-server = "enable"
SYSTEMD_AUTO_ENABLE:ank-agent = "enable"

INITSCRIPT_PACKAGES = "${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'ank-server ank-agent', '', d)}"
INITSCRIPT_NAME:ank-server = "ank-server"
INITSCRIPT_PARAMS:ank-server = "start 70 2 3 4 5 . stop 30 0 1 6 ."
INITSCRIPT_NAME:ank-agent = "ank-agent"
INITSCRIPT_PARAMS:ank-agent = "start 71 2 3 4 5 . stop 29 0 1 6 ."

do_install() {
    # Install binaries
    install -d ${D}${bindir}
    install -m 0755 ${B}/target/${CARGO_TARGET_SUBDIR}/ank-server ${D}${bindir}/
    install -m 0755 ${B}/target/${CARGO_TARGET_SUBDIR}/ank-agent ${D}${bindir}/
    install -m 0755 ${B}/target/${CARGO_TARGET_SUBDIR}/ank ${D}${bindir}/

    # Install configuration directory
    install -d ${D}${sysconfdir}/ankaios
    install -m 0644 ${UNPACKDIR}/state.yaml ${D}${sysconfdir}/ankaios/
    install -m 0644 ${UNPACKDIR}/ank.conf ${D}${sysconfdir}/ankaios/
    install -m 0644 ${UNPACKDIR}/ank-server.conf ${D}${sysconfdir}/ankaios/
    install -m 0644 ${UNPACKDIR}/ank-agent.conf ${D}${sysconfdir}/ankaios/

    if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
        install -d ${D}${systemd_system_unitdir}
        install -m 0644 ${UNPACKDIR}/ank-server.service ${D}${systemd_system_unitdir}/
        install -m 0644 ${UNPACKDIR}/ank-agent.service ${D}${systemd_system_unitdir}/
    fi

    if ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'true', 'false', d)}; then
        install -d ${D}${sysconfdir}/init.d
        install -m 0755 ${UNPACKDIR}/init-scripts/ank-server ${D}${sysconfdir}/init.d/ank-server
        install -m 0755 ${UNPACKDIR}/init-scripts/ank-agent ${D}${sysconfdir}/init.d/ank-agent

        install -d ${D}${sysconfdir}/default
        install -m 0644 ${UNPACKDIR}/ank-server.default ${D}${sysconfdir}/default/ank-server
        install -m 0644 ${UNPACKDIR}/ank-agent.default ${D}${sysconfdir}/default/ank-agent
    fi

}
