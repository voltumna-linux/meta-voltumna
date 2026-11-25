# e500v2 SPE: OpenEmbedded's cross-canadian.bbclass forces TARGET_OS=linux for the
# PowerPC SDK compiler (it zeroes ABIEXTENSION and falls into the final
# "else: d.setVar('TARGET_OS', 'linux')"). The relocatable cross-canadian gcc is then
# configured --target=powerpc-<vendor>-linux, i.e. an rs6000 cross, which since the
# powerpcspe split (GCC 9+) no longer carries -mspe/-mfloat-gprs. The target/native gcc
# and gcc-cross keep the gnuspe triple (powerpcspe backend) and work; only the SDK
# compiler is broken.
#
# Restore the gnuspe target for the SPE SDK compiler so GCC selects the powerpcspe
# backend (which provides -mspe/-mfloat-gprs) and the SDK matches the gnuspe target
# sysroot. This anonymous python runs after cross-canadian.bbclass's one (bbappends are
# parsed last), so it overrides the TARGET_OS=linux set there.
python () {
    if d.getVar("TARGET_ARCH") == "powerpc" and bb.utils.contains("TUNE_FEATURES", "spe", True, False, d):
        d.setVar("TARGET_OS", "linux-gnuspe")
        d.setVar("ABIEXTENSION", "spe")
        # keep the plain powerpc-*-linux-* tool aliases as well
        d.appendVar("CANADIANEXTRAOS", " linux")
}
