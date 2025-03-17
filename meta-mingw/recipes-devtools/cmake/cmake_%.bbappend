DEPENDS_remove_mingw32 = "ncurses"

cmake_do_generate_toolchain_file_append_mingw32() {
    cat >> ${WORKDIR}/toolchain.cmake <<EOF
set( CMAKE_SYSTEM_NAME Windows )
EOF
}
