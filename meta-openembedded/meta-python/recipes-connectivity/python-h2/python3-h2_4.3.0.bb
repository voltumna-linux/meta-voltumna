DESCRIPTION = "HTTP/2 State-Machine based protocol implementation"
HOMEPAGE = "https://github.com/python-hyper/hyper-h2"
LICENSE = "MIT"

LIC_FILES_CHKSUM = "file://LICENSE;md5=aa3b9b4395563dd427be5f022ec321c1"

SRC_URI[sha256sum] = "6c59efe4323fa18b47a632221a1888bd7fde6249819beda254aeca909f221bf1"

inherit pypi python_setuptools_build_meta

RDEPENDS:${PN} += "python3-hpack python3-hyperframe"
