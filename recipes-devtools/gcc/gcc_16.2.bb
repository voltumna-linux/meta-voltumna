require recipes-devtools/gcc/gcc-${PV}.inc
require gcc-target.inc

# The generic check only looks inside the version directory the tarball lives
# in and would always report the current version: point it at the release
# index instead. Restrict the check to the 15.x series maintained here; widen
# the regex to (?P<pver>\d+\.\d+\.\d+) to follow all series (a new series also
# needs its gcc-X.Y.inc from openembedded-core).
UPSTREAM_CHECK_URI = "https://ftp.gnu.org/gnu/gcc/"
UPSTREAM_CHECK_REGEX = "gcc-(?P<pver>15\.\d+\.\d+)/"

# Building with thumb enabled on armv4t armv5t fails with
# | gcc-4.8.1-r0/gcc-4.8.1/gcc/cp/decl.c:7438:(.text.unlikely+0x2fa): relocation truncated to fit: R_ARM_THM_CALL against symbol `fancy_abort(char const*, int, char const*)' defined in .glue_7 section in linker stubs
# | gcc-4.8.1-r0/gcc-4.8.1/gcc/cp/decl.c:7442:(.text.unlikely+0x318): additional relocation overflows omitted from the output
ARM_INSTRUCTION_SET:armv4 = "arm"
ARM_INSTRUCTION_SET:armv5 = "arm"

ARMFPARCHEXT:armv6 = "${@'+fp' if d.getVar('TARGET_FPU') == 'hard' else ''}"
ARMFPARCHEXT:armv7a = "${@'+fp' if d.getVar('TARGET_FPU') == 'hard' else ''}"
ARMFPARCHEXT:armv7ve = "${@'+fp' if d.getVar('TARGET_FPU') == 'hard' else ''}"

LANGUAGES = "c,c++${FORTRAN},jit"

BBCLASSEXTEND = "nativesdk"
