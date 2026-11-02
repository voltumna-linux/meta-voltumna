# make[3]: *** No rule to make target 'overview.xml', needed by 'html-build.stamp'.  Stop.
EXTRA_OECONF_append = ' \
    --disable-gtk-doc  \
    '
