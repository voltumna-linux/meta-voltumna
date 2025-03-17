DESCRIPTION = "Andor SDK 3.x for CCD cameras"
HOMEPAGE = "https://andor.oxinst.com/downloads/"
LICENSE = "CLOSED"

SRC_URI = " \
        https://www.elettra.eu/images/Documents/Voltumna/intranet/predownloaded-tarballs/andor-sdk3-${PV}.tgz \
	"
SRC_URI[sha256sum] = "1fded8f237227bce605365e651776fec57abd4aabf7a97a0371d65479a2575a3"

COMPATIBLE_HOST = "x86_64.*-linux"
S = "${WORKDIR}/andor"
