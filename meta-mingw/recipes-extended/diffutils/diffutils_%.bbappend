FILESEXTRAPATHS_prepend_mingw32 := "${THISDIR}/${BPN}:"

# Add some definitions for POSIX signals..
CFLAGS_append_mingw32 = " -DSIGALRM=14 -DSIGHUP=1 -DSIGQUIT=3 -DSIGPIPE=13 -DSIGTSTP=18 -DSIGSTOP=17 "

do_configure_prepend_mingw32 () {
    # Remove building of "man" and "gnulib-tests". The tests don't
    # cross-compile for mingw, but we aren't using them anyway
    sed -i \
        -e 's:^SUBDIRS =\(.*\) man\>:SUBDIRS = \1 :g' \
        -e 's:^SUBDIRS =\(.*\) gnulib-tests\>:SUBDIRS = \1 :g' \
        ${S}/Makefile.am
}

