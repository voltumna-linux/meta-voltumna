LICENSE = "ZPL-2.1"
LIC_FILES_CHKSUM = "file://${WORKDIR}/mingw-w64-v${PV}/COPYING;md5=bb936f0e04d8f1e19ad545100cee9654"

COMPATIBLE_HOST = ".*-mingw.*"

SRC_URI = "${SOURCEFORGE_MIRROR}/project/mingw-w64/mingw-w64/mingw-w64-release/mingw-w64-v${PV}.tar.bz2"
SRC_URI[sha256sum] = "cc41898aac4b6e8dd5cffd7331b9d9515b912df4420a3a612b5ea2955bbeed2f"

UPSTREAM_CHECK_URI = "http://sourceforge.net/projects/mingw-w64/files/mingw-w64/mingw-w64-release/"
UPSTREAM_CHECK_REGEX = "mingw-w64-v(?P<pver>(\d+[\.\-_]*)+)\.tar"
#| Assembler messages:
#| i686-w64-mingw32-dlltool --as-flags=--32 -m i386 -k --as=i686-w64-mingw32-as  --output-lib lib32/libd3dcompiler_41.a  --input-def ../mingw-w64-v9.0.0/mingw-w64-crt/lib32/d3dcompiler_41.def
#| i686-w64-mingw32-dlltool: failed to open temporary tail file: D3DCompiler_dll_t.o: No such file or directory
PARALLEL_MAKE = ""
