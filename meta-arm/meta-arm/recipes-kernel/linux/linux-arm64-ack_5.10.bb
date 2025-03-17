# SPDX-License-Identifier: Apache-2.0
#
# Copyright (c) 2021 Arm Limited
#
require linux-arm64-ack.inc

SRC_URI = " \
    git://android.googlesource.com/kernel/common.git;protocol=https;branch=android12-5.10-lts \
    "

# tag: ASB-2021-09-05_12-5.10
SRCREV = "3d371f087c953c0e08a228169d4e5c44aea99416"
