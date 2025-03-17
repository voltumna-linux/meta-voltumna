DESCRIPTION = "Andor 2.x for CCD cameras"
HOMEPAGE = "https://andor.oxinst.com/downloads/"
LICENSE = "CLOSED"

SRC_URI = " \
        https://www.elettra.eu/images/Documents/Voltumna/intranet/predownloaded-tarballs/andor-${PV}.tar.gz \
	"
SRC_URI[sha256sum] = "08b9b6af9dd3d9bb7d62f760e00fa79f6fa832114dcc28c77403e6b9f895445f"

COMPATIBLE_HOST = "x86_64.*-linux"
S = "${WORKDIR}/andor"
