include dpdk.inc

CONFIG_NAME = "common_linux"
TEST_DIR = "app/test"

STABLE = "-stable"
BRANCH = "19.11"
SRCREV = "cd28195eaf5d0d089a2737106a2a9ce328b23844"

LICENSE = "BSD-3-Clause & LGPLv2.1 & GPLv2"
LIC_FILES_CHKSUM = "file://license/gpl-2.0.txt;md5=b234ee4d69f5fce4486a80fdaf4a4263 \
                    file://license/lgpl-2.1.txt;md5=4b54a1fd55a448865a0b32d41598759d \
                    file://license/bsd-3-clause.txt;md5=0f00d99239d922ffd13cabef83b33444"

do_install_append () {
    # Remove the unneeded dir
    rm -rf ${D}/${INSTALL_PATH}/${RTE_TARGET}/app
}

# CVE-2021-3839 has been fixed by commit aef547884b in 19.11
# NVD database is incomplete
# CVE-2022-28199 has been fixed by commit ef311075d2 in 19.11
# NVD database is incomplete
CVE_CHECK_WHITELIST  += "\
    CVE-2021-3839 \
    CVE-2022-28199 \
"
