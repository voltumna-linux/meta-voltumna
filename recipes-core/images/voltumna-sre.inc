require include/voltumna.inc
VARIANT = "Voltumna (Runtime)"

set_killuserprocess() {
	sed -ie 's,#KillUserProcesses=yes,KillUserProcesses=yes,g' ${IMAGE_ROOTFS}${sysconfdir}/systemd/logind.conf
}

ROOTFS_POSTPROCESS_COMMAND:append = " set_killuserprocess;"
