# Need to disable X11 explictly as nativesdk-libxdmcp fails:
# .libs/Fill.o:Fill.c:(.text+0x48): undefined reference to `_imp__recvfrom@24'
# .libs/Flush.o:Flush.c:(.text+0x36): undefined reference to `_imp__sendto@24'
PACKAGECONFIG:remove:mingw32:class-nativesdk = "x11 opengl"

# libtool doesn't think it can link windres output (COFF) with libtool objects
# (COFF) , but it can.  This might be because file misidentifies version.o:
#
# version.o: Targa image data - Map (0) 1 x 65536 x 0 +862 "\004\001.rsrc"
#
# Telling libtool to be dumb and just pass the input to the underlying tools
# works fine.
EXTRA_OECONF:append:mingw32 = " lt_cv_deplibs_check_method=pass_all"
