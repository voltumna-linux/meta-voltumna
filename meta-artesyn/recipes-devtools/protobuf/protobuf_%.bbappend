# Stessa motivazione di abseil-cpp_%.bbappend: libprotobuf.so usa atomiche 64-bit
# (-l)atomic verrebbe scartata da --as-needed se messa nella posizione standard.
# La forziamo in NEEDED tramite --no-as-needed locale.
# NB: il flag protobuf_HAVE_BUILTIN_ATOMICS è retaggio di protobuf 3.x, su 6.x
# non ha effetto e va rimosso per non confondere chi legge il bbappend.
LDFLAGS:append:powerpc = " -Wl,--push-state,--no-as-needed -latomic -Wl,--pop-state"

