# This file defines AMD Features that can be added as EXTRA_IMAGE_FEATURES to
# different machines based on what is supported on a machine (MACHINE_FEATURES)
# and which additional features a user is requesting through EXTRA_IMAGE_FEATURES.
# This gives a broad flexibility and control over packages being installed on a
# machine for any image without needing to create bbappends for all the images
# that are to be supported.
#
# > Each feature can contain packages and packagegroups as its components.
# > Feature components can be dependent on DISTRO, EXTRA_IMAGE_FEATURES, or any
#   variable in general other than a particular image's related variable so most
#   things should be based on global configs rather than image configs.
#   e.g.: Components of "amd-feature-graphics" may be dependent on "x11-base" as
#   an IMAGE_FEATURE. Some packages may only be included for a specific
#   DISTRO. Some packages may only be installed if user allows them in local.conf etc.
# > Each machine must add the requested features to EXTRA_IMAGE_FEATURES in its
#   own machine config file regardless of the image being built, if that particular
#   feature is not handled in the common fragments.
# > Each machine can also override feature components in its own machine config 
#   when adding the feature to EXTRA_IMAGE_FEATURES. e.g.: A feature may be added
#   to a specific machine with minimal (or extended) packages based on requirement.
#
# Features are classified as:
#
# * amd-misc-pkgs		: Intended for Platform Specific Packages, Common Packages to be added to all machines, etc.
# * amd-feature-multimedia	: Multimedia packages (it does not depend on graphics because a machine may not have a GUI but could play videos and sounds from console)
# * amd-feature-graphics	: Graphics packages
# * amd-feature-networking	: Networking packages
# * amd-feature-debug-profile	: Debugging and Profiling tools
# * <add more features here>	: <feature summary>

GSTREAMER_PKGS ?= " \
    ${@bb.utils.contains("IMAGE_FEATURES", "x11-base", "gstreamer1.0-meta-x11-base", "", d)} \
    ${@bb.utils.contains("COMBINED_FEATURES", "alsa", "gstreamer1.0-meta-audio", "", d)} \
    gstreamer1.0-meta-debug \
    gstreamer1.0-meta-video \
    ${@bb.utils.contains("IMAGE_FEATURES", "x11-base", "gstreamer1.0-omx", "", d)} \
    ${@bb.utils.contains("IMAGE_FEATURES", "x11-base", "gstreamer1.0-vaapi", "", d)} \
"
VULKAN_PKGS ?= ""
CODEXL_PKGS ?= ""
DPDK_PKGS ?= ""

# Additional packages can be added to the following feature specific
# variables from each machine's config file
AMD_PLATFORM_SPECIFIC_PKGS ?= ""
AMD_FEATURE_MULTIMEDIA_PKGS ?= ""
AMD_FEATURE_GRAPHICS_PKGS ?= ""
AMD_FEATURE_NETWORKING_PKGS ?= ""
AMD_FEATURE_DEBUG_PROFILE_PKGS ?= ""

FEATURE_PACKAGES_amd-misc-pkgs = "\
    bc \
    ${AMD_PLATFORM_SPECIFIC_PKGS} \
"

FEATURE_PACKAGES_amd-feature-multimedia = "\
    ${GSTREAMER_PKGS} \
    ${@bb.utils.contains("IMAGE_FEATURES", "x11-base", "vdpauinfo", "", d)} \
    ${AMD_FEATURE_MULTIMEDIA_PKGS} \
"

FEATURE_PACKAGES_amd-feature-graphics = "\
    ${@bb.utils.contains("INCLUDE_VULKAN", "yes", "${VULKAN_PKGS}", "", d)} \
    ${AMD_FEATURE_GRAPHICS_PKGS} \
"
FEATURE_PACKAGES_amd-feature-graphics:append:radeon = " ${@bb.utils.contains("IMAGE_FEATURES", "x11-base", "mesa-demos", "", d)}"

FEATURE_PACKAGES_amd-feature-networking = "\
    ${DPDK_PKGS} \
    strongswan \
    ${AMD_FEATURE_NETWORKING_PKGS} \
"

FEATURE_PACKAGES_amd-feature-debug-profile = "\
    ${@bb.utils.contains("INCLUDE_CODEXL", "yes", "${CODEXL_PKGS}", "", d)} \
    ${AMD_FEATURE_DEBUG_PROFILE_PKGS} \
"
