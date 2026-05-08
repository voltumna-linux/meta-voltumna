# Le 32-bit PowerPC (ppce500v2 SPE su MVME2500, ppc7400 su MVME5100) non hanno
# istruzioni atomiche 64-bit inline: GCC genera chiamate a __atomic_*_8 fornite
# da libatomic. La build di abseil con i flag globali Yocto colloca -latomic
# prima degli oggetti, e -Wl,--as-needed (impostato in TARGET_LDFLAGS) la scarta
# dal DT_NEEDED delle libabsl_*.so. Forziamo l'inclusione con --no-as-needed
# locale, così le libabsl_*.so dichiarano libatomic.so.1 come NEEDED.
LDFLAGS:append:powerpc = " -Wl,--push-state,--no-as-needed -latomic -Wl,--pop-state"

