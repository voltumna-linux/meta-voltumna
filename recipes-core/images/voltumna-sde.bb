require include/voltumna.inc

EXTRA_IMAGE_FEATURES += "debug-tweaks dev-pkgs bash-completion-pkgs doc-pkgs dbg-pkgs tools-sdk tools-debug tools-profile"

IMAGE_INSTALL_append += " devmem2 git gzip cmake kernel-devsrc prepare-kernel-devsrc glib-2.0-utils"
IMAGE_INSTALL_append_arm += " dtc"
