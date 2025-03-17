# GCC-14 treats this warning as error which results in
# build failures
CFLAGS:append:mingw32 = " -Wno-error=incompatible-pointer-types"
