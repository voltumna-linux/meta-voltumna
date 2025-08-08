# Copyright (C) 2019 Garmin Ltd. or its subsidiaries
# Released under the MIT license (see COPYING.MIT for the terms)

require ${COREBASE}/meta/recipes-core/images/core-image-minimal.bb

# Other recipes that should be tested as part of the SDK in case some one wants
# to include them
TOOLCHAIN_HOST_TASK += "\
    nativesdk-curl \
    nativesdk-dbus-tools \
    nativesdk-dtc \
    nativesdk-libarchive \
    nativesdk-ninja \
    nativesdk-swig \
    nativesdk-wayland \
    "
