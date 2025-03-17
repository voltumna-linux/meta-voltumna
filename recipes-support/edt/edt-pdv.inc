DESCRIPTION = "PDV Software - For all EDT digital image capture boards, including the VisionLink, DVa and DV series boards for PCI Express, PCI, PMC, and Compact PCI."
HOMEPAGE = "https://edt.com/file-category/pdv/"
LICENSE = "CLOSED"

SRC_URI = " \
        https://www.elettra.eu/images/Documents/Voltumna/intranet/predownloaded-tarballs/EDTpdv_lnx_${PV}.run \
	"
SRC_URI[sha256sum] = "bcf3c4f52a8fbf51961b27e2281ce1ca630c8da9e52ed0f1c32e6395b6da09a3"

COMPATIBLE_HOST = "x86_64.*-linux"

do_extract_data() {
	chmod +x ${WORKDIR}/EDTpdv_lnx_${PV}.run
	${WORKDIR}/EDTpdv_lnx_${PV}.run --noexec --target ${S}
}

python do_unpack:append() {
    bb.build.exec_func('do_extract_data', d)
}

