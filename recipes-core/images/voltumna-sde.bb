require include/voltumna.inc

EXTRA_IMAGE_FEATURES:append = " debug-tweaks dev-pkgs bash-completion-pkgs \
	doc-pkgs src-pkgs dbg-pkgs tools-sdk tools-debug tools-profile"

IMAGE_INSTALL:append = " devmem2 git gzip cmake meson kernel-devsrc \
	prepare-kernel-devsrc glib-2.0-utils info man-pages"
IMAGE_INSTALL:append:arm = " dtc"
