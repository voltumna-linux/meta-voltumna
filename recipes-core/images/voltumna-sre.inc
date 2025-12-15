require include/voltumna.inc
VARIANT = "Voltumna (Runtime)"

set_killuserprocess() {
	sed -ie 's,#KillUserProcesses=yes,KillUserProcesses=yes,g' ${IMAGE_ROOTFS}${sysconfdir}/systemd/logind.conf
}

set_runtime_lib() {
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}${sysconfdir}/runtime-lib.conf
        LD_LIBRARY_PATH=/runtime/lib
	__EOF__
	cat <<-__EOF__ >> ${IMAGE_ROOTFS}${sysconfdir}/profile.d/runtime-lib.sh
        set -a
        source /etc/runtime-lib.conf
        set +a
	__EOF__
}

ROOTFS_POSTPROCESS_COMMAND:append = " set_killuserprocess; set_runtime_lib;"
