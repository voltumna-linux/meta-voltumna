SUMMARY = "pam-ssh-agent-auth"
DESCRIPTION = "A PAM module which permits authentication via ssh-agent."
HOMEPAGE = "http://sourceforge.net/projects/pamsshagentauth/"
SECTION = "libs"
LICENSE = "OpenSSL & BSD-2-Clause & BSD-3-Clause"
LIC_FILES_CHKSUM = "file://LICENSE.OpenSSL;md5=8ab01146141ded59b75f8ba7811ed05a \
                    file://OPENSSH_LICENSE;md5=7ae09218173be1643c998a4b71027f9b \
"

SRC_URI = "http://sourceforge.net/projects/pamsshagentauth/files/pam_ssh_agent_auth/v${PV}/pam_ssh_agent_auth-${PV}.tar.bz2 \
           file://0001-Adapt-to-OpenSSL-1.1.1.patch \
           file://0002-Check-against-the-correct-OPENSSL_VERSION_NUMBER.patch \
           file://0001-configure-Include-stdio.h-for-printf.patch \
           "
SRC_URI[sha256sum] = "3c53d358d6eaed1b211239df017c27c6f9970995d14102ae67bae16d4f47a763"

DEPENDS += "libpam openssl"

inherit features_check
REQUIRED_DISTRO_FEATURES = "pam"

# This gets us ssh-agent, which we are almost certain to want.
#
RDEPENDS:${PN} += "openssh-misc"

# Kind of unfortunate to have underscores in the name.
#
S = "${UNPACKDIR}/pam_ssh_agent_auth-${PV}"

inherit autotools-brokensep perlnative

# Avoid autoreconf.  Override the --libexec oe_runconf specifies so that
# the module is put with the other pam modules.  Because it cannot, in general,
# do a runtime test, configure wants to use rpl_malloc() and rpl_realloc()
# instead of malloc() and realloc().  We set variables to tell it not to because
# these functions do not exist.
#
do_configure () {
    install -m 0755 ${STAGING_DATADIR_NATIVE}/gnu-config/config.guess ${S}
    install -m 0755 ${STAGING_DATADIR_NATIVE}/gnu-config/config.sub ${S}
    oe_runconf --without-openssl-header-check  --libexecdir=${base_libdir}/security \
               ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes
}

# Link with CC.  Configure cannot figure out the correct AR.
#
do_compile () {
    oe_runmake  LD="${CC}" AR="${AR}"
}

# This stuff is not any place looked at by default.
#
FILES:${PN} += "${base_libdir}/security/pam*"
FILES:${PN}-dbg += "${base_libdir}/security/.debug"

# This one is reproducible only on 32bit MACHINEs
# http://errors.yoctoproject.org/Errors/Details/766965/
# ssh-rsa.c:59:24: error: passing argument 1 of 'EVP_DigestInit' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-rsa.c:60:26: error: passing argument 1 of 'EVP_DigestUpdate' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-rsa.c:61:25: error: passing argument 1 of 'EVP_DigestFinal' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-ecdsa.c:76:18: error: passing argument 1 of 'DSA_SIG_get0' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-ecdsa.c:76:23: error: passing argument 2 of 'DSA_SIG_get0' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-ecdsa.c:76:27: error: passing argument 3 of 'DSA_SIG_get0' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-ecdsa.c:148:18: error: passing argument 1 of 'DSA_SIG_get0' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-ecdsa.c:148:23: error: passing argument 2 of 'DSA_SIG_get0' from incompatible pointer type [-Wincompatible-pointer-types]
# ssh-ecdsa.c:148:27: error: passing argument 3 of 'DSA_SIG_get0' from incompatible pointer type [-Wincompatible-pointer-types]
CFLAGS += "-Wno-error=incompatible-pointer-types"
