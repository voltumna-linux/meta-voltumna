require include/voltumna.inc

EXTRA_IMAGE_FEATURES += "debug-tweaks dev-pkgs bash-completion-pkgs doc-pkgs dbg-pkgs tools-sdk tools-debug tools-profile"

IMAGE_INSTALL_append += " vim devmem2 git gzip cmake kernel-devsrc prepare-kernel-devsrc"
IMAGE_INSTALL_append_arm += " dtc"
