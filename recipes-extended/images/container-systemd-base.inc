SUMMARY ?= "Sample systemd system container"
DESCRIPTION ?= "A small systemd system container which will run \
                the application defined in IMAGE_INSTALL."

LICENSE ?= "MIT"
LIC_FILES_CHKSUM ?= "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

# Some commands of interest:
# % docker run -d --rm --name systemd_test  --privileged \
#    --cap-add SYS_ADMIN --security-opt seccomp=unconfined --cgroup-parent=docker.slice \
#    --cgroupns private --tmpfs /tmp --tmpfs /run --tmpfs /run/lock zeddii/systemd-container-base
#
# % docker run -d --rm --name systemd_test --privileged \
#    --cgroup-parent=docker.slice --cgroupns private  zeddii/c3-systemd-container
#
# % docker inspect systemd_test
# % docker inspect systemd_test | grep \"IPAddress\":
# % docker exec systemd_test bash -c "echo 'testuser:password' | chpasswd"
# % ssh testuser@172.17.0.2

require container-base.bb

OCI_IMAGE_ENTRYPOINT = "/sbin/init"

IMAGE_INSTALL:append = " systemd"
IMAGE_INSTALL:append = " packagegroup-core-base-utils"
IMAGE_INSTALL:append = " packagegroup-core-ssh-openssh"
IMAGE_INSTALL:append = " busybox"
IMAGE_INSTALL:append = " container-systemd-config"

IMAGE_FEATURES ?= ""

NO_RECOMMENDATIONS = "1"
