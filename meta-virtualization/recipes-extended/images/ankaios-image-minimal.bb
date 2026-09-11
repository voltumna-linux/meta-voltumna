SUMMARY = "Minimal image to boot and test Eclipse Ankaios end-to-end in QEMU"
DESCRIPTION = "A small reference image that lands the Ankaios server, agent and \
ank CLI together with the podman runtime and a state.yaml manifest. \
It boots on qemux86-64 and starts a demo workload so the orchestrator can be \
exercised end-to-end. See README-ankaios.md for the boot/verify/teardown steps."

LICENSE = "Apache-2.0"

inherit core-image features_check

# Podman needs virtualization + seccomp; systemd is required because it mounts
# cgroups and sets up DNS out of the box, which the sysvinit path does not.
REQUIRED_DISTRO_FEATURES ?= "virtualization seccomp systemd"

# Reference target documented in README-ankaios.md
COMPATIBLE_MACHINE = "qemux86-64"

# Debug/test image: passwordless root login on the serial console
IMAGE_FEATURES += "allow-empty-password empty-root-password allow-root-login"

# ankaios pulls server + agent + ank CLI; podman is the workload runtime the
# agent shells out to for the hello-world state.yaml below.
IMAGE_INSTALL:append = " ankaios podman"

# Headroom (1 GB) for the workload container image podman pulls at runtime
IMAGE_ROOTFS_EXTRA_SPACE = "1000000"

# Capture the in-layer path at parse time (only valid during parsing, hence
# ':='), and track it so do_rootfs reruns when state.yaml changes.
STATE_YAML_SRC := "${THISDIR}/${PN}/state.yaml"
do_rootfs[file-checksums] += "${STATE_YAML_SRC}:True"

# Override the (empty) default state.yaml shipped by ank-server with one that
# defines the hello-ankaios workload.
ROOTFS_POSTPROCESS_COMMAND += "install_ankaios_test_state;"
install_ankaios_test_state() {
    install -d ${IMAGE_ROOTFS}${sysconfdir}/ankaios
    install -m 0644 ${STATE_YAML_SRC} ${IMAGE_ROOTFS}${sysconfdir}/ankaios/state.yaml
}
