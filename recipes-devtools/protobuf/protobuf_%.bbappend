#EXTRA_OECMAKE:append:ppce500v2 = " -Dprotobuf_HAVE_BUILTIN_ATOMICS=ON"
#EXTRA_OECMAKE:append:ppc7400 = " -Dprotobuf_HAVE_BUILTIN_ATOMICS=ON"

#TARGET_LDFLAGS:append:ppce500v2:class-target = " -latomic "
#LDFLAGS:append:ppc7400:class-target = " -latomic "
#LDFLAGS:append:ppc7400:class-native = " -latomic "

EXTRA_OECMAKE:append:powerpc = " -Dprotobuf_HAVE_BUILTIN_ATOMICS=ON"
#LDFLAGS:append:powerpc = " -latomic "
#BUILD_LDFLAGS:append = " -latomic "
#TARGET_LDFLAGS:append = " -latomic "
