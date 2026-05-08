#LDFLAGS:append:powerpc:class-target = " -latomic"
#LDFLAGS:append:powerpc:class-native = " -latomic"
LDFLAGS:append:powerpc = " -latomic"


#EXTRA_OECMAKE:append:powerpc = " -DCMAKE_SHARED_LINKER_FLAGS='-latomic'"
#EXTRA_OECMAKE:append:powerpc = " -DCMAKE_SHARED_LINKER_FLAGS='${LDFLAGS} -latomic'"
# TARGET_LDFLAGS:append:powerpc = " -latomic "

