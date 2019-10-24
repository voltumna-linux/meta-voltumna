require include/voltumna.inc

EXTRA_IMAGE_FEATURES += "debug-tweaks dev-pkgs doc-pkgs dbg-pkgs tools-sdk tools-debug tools-profile"

IMAGE_INSTALL_append += " vim devmem2 git gzip kernel-devsrc cmake"
IMAGE_INSTALL_append_arm += " dtc"

#make_prepare() {
#		
#}
#
# IMAGE_PREPROCESS_COMMAND_append += " make_prepare"

