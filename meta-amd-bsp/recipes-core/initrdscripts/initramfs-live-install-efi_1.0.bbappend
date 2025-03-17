FILESEXTRAPATHS:prepend := "${THISDIR}/files:"
SRC_URI:append:amd = " \
     file://0003-init-install-efi.sh-Don-t-set-quiet-kernel-option-in.patch;striplevel=0;patchdir=${WORKDIR} \
     file://0004-init-install-efi.sh-Add-a-second-prompt-to-install.patch;striplevel=0;patchdir=${WORKDIR} \
"
