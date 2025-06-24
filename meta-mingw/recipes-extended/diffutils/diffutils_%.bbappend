FILESEXTRAPATHS:prepend:mingw32 := "${THISDIR}/${BPN}:"

# Add some definitions for POSIX signals..
CFLAGS:append:mingw32 = " -DSIGALRM=14 -DSIGHUP=1 -DSIGQUIT=3 -DSIGPIPE=13 -DSIGTSTP=18 -DSIGSTOP=17 "

SRC_URI:append:mingw32 = "\
       file://0001-sdiff-Match-execvp-argument-types.patch \
       "

do_configure:prepend:mingw32 () {
    # Remove building of "man" and "gnulib-tests". The tests don't
    # cross-compile for mingw, but we aren't using them anyway
    sed -i \
        -e 's:^SUBDIRS =\(.*\) man\>:SUBDIRS = \1 :g' \
        -e 's:^SUBDIRS =\(.*\) gnulib-tests\>:SUBDIRS = \1 :g' \
        ${S}/Makefile.am
}
