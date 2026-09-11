SUMMARY = "User space components of the Ceph file system"
LICENSE = "Apache-2.0 AND BSL-1.0 AND GPL-2.0-only AND LGPL-2.1-only AND MIT AND Zlib"
LIC_FILES_CHKSUM = "file://COPYING-LGPL2.1;md5=fbc093901857fcd118f065f900982c24 \
                    file://COPYING-GPL2;md5=b234ee4d69f5fce4486a80fdaf4a4263 \
                    file://COPYING;md5=2f83d608c026a3156e4c186721954da2 \
"
inherit cmake pkgconfig python3native python3-dir systemd useradd
# Disable python pybind support for ceph temporary, when corss compiling pybind,
# pybind mix cmake and python setup environment, would case a lot of errors.

# Ceph's gitsm:// fetch hits "Unable to find revision <sha> in branch  even
# from upstream" failures because the project pins submodule commits that
# upstream periodically loses (force-pushes, branch reaps, etc.). Exploded
# into explicit git:// entries so each SRCREV can be carried/fixed-up here
# without depending on the submodule remote staying intact. SRCREVs below
# are from `git submodule status` at the main SRCREV.
SRCREV_FORMAT = "ceph"
SRCREV_ceph = "98d05bca3f179facf2a268657c7418d1f79d7854"
SRCREV_ceph_object_corpus = "530602c5f31d68595495593027439838c459b1eb"
SRCREV_jerasure = "96c76b89d661c163f65a014b8042c9354ccf7f31"
SRCREV_gf_complete = "7e61b44404f0ed410c83cfd3947a52e88ae044e1"
SRCREV_rocksdb = "c7a7c6340c522d2ecc21625e2b726554cb61eb72"
SRCREV_ceph_erasure_code_corpus = "2d7d78b9cc52e8a9529d8cc2d2954c7d375d5dd7"
SRCREV_googletest = "6910c9d9165801d8827d628cb72eb7ea9dd538c5"
SRCREV_spdk = "82fcb248516816f19bee2c8f598149067e16a4bd"
SRCREV_xxHash = "e573d4d2aaeaba0f3e5a0a9a54144a1f2b4b56e7"
SRCREV_isa_l = "7c3479e0a9dac17f448603ec1ad64c7c625f530c"
SRCREV_zstd = "794ea1b0afca0f020f4e57b6732332231fb23c70"
SRCREV_isa_l_crypto = "c353c2d021c03cfc6180ddf9e28a24b3b61e9760"
SRCREV_librdkafka = "e1db7eaa517f0a6438bc846a9c49ede73b9ea211"
SRCREV_blkin = "f24ceec055ea236a093988237a9821d145f5f7c8"
SRCREV_seastar = "cced0236ee7cb4e157b5a37fd9076d62c5be4f58"
SRCREV_fmt = "123913715afeb8a437e6388b4473fcc4753e1c9a"
SRCREV_c_ares = "fd6124c74da0801f23f9d324559d8b66fb83f533"
SRCREV_rook_client_python = "82673cd7c7a3f4919b98706985ff27e57d2c1b94"
SRCREV_s3select = "0a0f6d439441f5b121ed1052dac54542e4f1d89b"
SRCREV_libkmip = "c05329f82a1a0e6d9bc4bae6fb25ce3d8e733f6c"
SRCREV_arrow = "272715f6df2a042d69881ffa03d5078c58e4b345"
SRCREV_utf8proc = "d7bf128df773c2a1a7242eb80e51e91a769fc985"
SRCREV_opentelemetry_cpp = "95fe422d56d74ded3640c5cdcaa3011bc9e18f68"
SRCREV_qatlib = "142e305970ec66a860945d20bb7c330f99ed900b"
SRCREV_qatzip = "fdee557b5bb640827758f121102dcf3583292b7a"
SRCREV_BLAKE3 = "92e4cd71be48fdf9a79e88ef37b8f415ec5ac210"
SRCREV_gateway = "5e04ca9a89c5333004d2c3ff8114d91f0d0deac4"
SRCREV_breakpad = "41b6533e5f3dd7f0320ef58608ee32e8e4f132fb"
SRCREV_lss = "ed31caa60f20a4f6569883b2d752ef7522de51e0"
# Nested submodules of s3select (s3select itself has a .gitmodules):
SRCREV_rapidjson = "fcb23c2dbf561ec0798529be4f66394d3e4996d8"
SRCREV_csvparser = "5a417973b4cea674a5e4a3b88a23098a2ab75479"

SRC_URI = "git://github.com/ceph/ceph.git;name=ceph;branch=main;protocol=https \
           git://github.com/ceph/ceph-object-corpus.git;name=ceph_object_corpus;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/ceph-object-corpus;nobranch=1;protocol=https \
           git://github.com/ceph/jerasure.git;name=jerasure;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/erasure-code/jerasure/jerasure;nobranch=1;protocol=https \
           git://github.com/ceph/gf-complete.git;name=gf_complete;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/erasure-code/jerasure/gf-complete;nobranch=1;protocol=https \
           git://github.com/ceph/rocksdb;name=rocksdb;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/rocksdb;nobranch=1;protocol=https \
           git://github.com/ceph/ceph-erasure-code-corpus.git;name=ceph_erasure_code_corpus;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/ceph-erasure-code-corpus;nobranch=1;protocol=https \
           git://github.com/ceph/googletest;name=googletest;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/googletest;nobranch=1;protocol=https \
           git://github.com/ceph/spdk.git;name=spdk;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/spdk;nobranch=1;protocol=https \
           git://github.com/ceph/xxHash.git;name=xxHash;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/xxHash;nobranch=1;protocol=https \
           git://github.com/intel/isa-l;name=isa_l;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/isa-l;nobranch=1;protocol=https \
           git://github.com/facebook/zstd;name=zstd;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/zstd;nobranch=1;protocol=https \
           git://github.com/intel/isa-l_crypto;name=isa_l_crypto;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/crypto/isa-l/isa-l_crypto;nobranch=1;protocol=https \
           git://github.com/confluentinc/librdkafka.git;name=librdkafka;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/librdkafka;nobranch=1;protocol=https \
           git://github.com/ceph/blkin;name=blkin;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/blkin;nobranch=1;protocol=https \
           git://github.com/ceph/seastar.git;name=seastar;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/seastar;nobranch=1;protocol=https \
           git://github.com/ceph/fmt.git;name=fmt;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/fmt;nobranch=1;protocol=https \
           git://github.com/ceph/c-ares.git;name=c_ares;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/c-ares;nobranch=1;protocol=https \
           git://github.com/ceph/rook-client-python.git;name=rook_client_python;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/pybind/mgr/rook/rook-client-python;nobranch=1;protocol=https \
           git://github.com/ceph/s3select.git;name=s3select;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/s3select;nobranch=1;protocol=https \
           git://github.com/Tencent/rapidjson.git;name=rapidjson;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/s3select/rapidjson;nobranch=1;protocol=https \
           git://github.com/ben-strasser/fast-cpp-csv-parser.git;name=csvparser;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/s3select/include/csvparser;nobranch=1;protocol=https \
           git://github.com/ceph/libkmip;name=libkmip;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/libkmip;nobranch=1;protocol=https \
           git://github.com/apache/arrow.git;name=arrow;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/arrow;nobranch=1;protocol=https \
           git://github.com/JuliaStrings/utf8proc;name=utf8proc;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/utf8proc;nobranch=1;protocol=https \
           git://github.com/ceph/opentelemetry-cpp.git;name=opentelemetry_cpp;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/jaegertracing/opentelemetry-cpp;nobranch=1;protocol=https \
           git://github.com/intel/qatlib.git;name=qatlib;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/qatlib;nobranch=1;protocol=https \
           git://github.com/intel/qatzip.git;name=qatzip;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/qatzip;nobranch=1;protocol=https \
           git://github.com/BLAKE3-team/BLAKE3.git;name=BLAKE3;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/BLAKE3;nobranch=1;protocol=https \
           git://github.com/ceph/ceph-nvmeof.git;name=gateway;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/nvmeof/gateway;nobranch=1;protocol=https \
           git://chromium.googlesource.com/breakpad/breakpad;name=breakpad;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/breakpad;nobranch=1;protocol=https \
           git://chromium.googlesource.com/linux-syscall-support;name=lss;subdir=${BB_GIT_DEFAULT_DESTSUFFIX}/src/lss;nobranch=1;protocol=https \
           file://0001-fix-host-library-paths-were-used.patch \
           file://ceph.conf \
           file://0001-cmake-use-FindBoost-instead-of-Boost-cmake-config.patch \
           file://0001-delete-install-layout-deb.patch \
           file://0001-cephadm-build.py-avoid-using-python3-from-sysroot-wh.patch \
           file://0001-rados-setup.py-allow-incompatible-pointer-types.patch \
           file://0001-rgw-setup.py-allow-incompatible-pointer-types.patch \
           file://0001-cmake-Distutils-include-CMAKE_C_COMPILER_ARG1-in-PY_.patch \
	   "

PV = "21.3.0+git"

DEPENDS = "boost bzip2 curl cryptsetup expat gperf-native \
           keyutils libaio liburing lua lz4 \
           nspr nss ninja-native \
           oath openldap openssl \
           python3 python3-native python3-cython-native python3-pip-native python3-pyyaml-native \
	   rabbitmq-c snappy thrift udev \
           valgrind xfsprogs zlib libgcc zstd re2 \
           lmdb	autoconf-native automake-native \
"


OECMAKE_C_COMPILER = "${@oecmake_map_compiler('CC', d)[0]} --sysroot=${RECIPE_SYSROOT}"
OECMAKE_CXX_COMPILER = "${@oecmake_map_compiler('CXX', d)[0]} --sysroot=${RECIPE_SYSROOT}"

USERADD_PACKAGES = "${PN}"
USERADD_PARAM:${PN} = "--system --user-group --home-dir /var/lib/ceph --shell /sbin/nologin ceph"

SYSTEMD_SERVICE:${PN} = " \
        ceph-radosgw@.service \
        ceph-radosgw.target \
        ceph-mon@.service \
        ceph-mon.target \
        ceph-mds@.service \
        ceph-mds.target \
        ceph-osd@.service \
        ceph-osd.target \
        cephfs-mirror@.service \
        cephfs-mirror.target \
        ceph.target \
        ceph-rbd-mirror@.service \
        ceph-rbd-mirror.target \
        ceph-volume@.service \
        ceph-mgr@.service \
        ceph-mgr.target \
        ceph-crash.service \
        ceph-exporter@.service \
        rbdmap.service \
        ceph-immutable-object-cache@.service \
        ceph-immutable-object-cache.target \
"

EXTRA_OECMAKE += "-DWITH_MANPAGE=OFF \
                 -DWITH_JAEGER=OFF \
                 -DWITH_SYSTEM_ZSTD=ON \
                 -DWITH_FUSE=OFF \
                 -DWITH_SPDK=OFF \
                 -DWITH_LEVELDB=OFF \
                 -DWITH_LTTNG=OFF \
                 -DWITH_BABELTRACE=OFF \
                 -DWITH_TESTS=OFF \
                 -DWITH_CATCH2=OFF \
                 -DWITH_BREAKPAD=OFF \
                 -DWITH_RADOSGW_SELECT_PARQUET=OFF \
                 -DWITH_RADOSGW_ARROW_FLIGHT=OFF \
                 -DWITH_MGR=OFF \
                 -DWITH_MGR_DASHBOARD_FRONTEND=OFF \
                 -DWITH_SYSTEM_BOOST=ON \
                 -DBoost_NO_BOOST_CMAKE=ON \
                 -DBOOST_ROOT=${RECIPE_SYSROOT}/usr \
                 -DBoost_NO_SYSTEM_PATHS=ON \
                 -DBoost_INCLUDE_DIR=${RECIPE_SYSROOT}/usr/include \
                 -DBoost_LIBRARY_DIR=${RECIPE_SYSROOT}/usr/lib \
                 -DWITH_RDMA=OFF \
		 -DWITH_RBD=OFF \
		 -DWITH_KRBD=OFF \
                 -DWITH_RADOSGW_AMQP_ENDPOINT=OFF \
                 -DWITH_RADOSGW_KAFKA_ENDPOINT=OFF \
                 -DWITH_REENTRANT_STRSIGNAL=ON \
		 -DWITH_PYTHON3=${PYTHON_BASEVERSION} \
		 -DPYTHON_DESIRED=3 \
		 -DCMAKE_TOOLCHAIN_FILE:FILEPATH=${WORKDIR}/toolchain.cmake \
		 -DCEPHADM_BUNDLED_DEPENDENCIES=none \
		 "

# -DWITH_SYSTEM_ROCKSDB=ON

do_configure:prepend () {
	# CMake 4.x writes an unbounded CMakeConfigureLog.yaml that explodes
	# with OE's long PATH — pre-create it as a symlink to /dev/null
	mkdir -p ${B}/CMakeFiles
	ln -sf /dev/null ${B}/CMakeFiles/CMakeConfigureLog.yaml

	echo "set( CMAKE_SYSROOT \"${RECIPE_SYSROOT}\" )" >> ${WORKDIR}/toolchain.cmake
	echo "set( CMAKE_DESTDIR \"${D}\" )" >> ${WORKDIR}/toolchain.cmake
	echo "set( PYTHON_SITEPACKAGES_DIR \"${PYTHON_SITEPACKAGES_DIR}\" )" >> ${WORKDIR}/toolchain.cmake
	# echo "set( CMAKE_C_COMPILER_WORKS TRUE)" >> ${WORKDIR}/toolchain.cmake
	# echo "set( CMAKE_CXX_COMPILER_FORCED TRUE)" >> ${WORKDIR}/toolchain.cmake
	echo "set( CMAKE_C_COMPILER_FORCED TRUE )" >> ${WORKDIR}/toolchain.cmake

	echo "set( WITH_QATDRV OFF )" >> ${WORKDIR}/toolchain.cmake
	echo "set( WITH_QATZIP OFF )" >> ${WORKDIR}/toolchain.cmake
	# cephfs-tool (added on the v20.3.0-tip line) unconditionally links
	# uring::uring with no WITH_LIBURING guard, so disabling liburing
	# leaves an undefined CMake target. Use system liburing instead.
	echo "set( WITH_LIBURING ON )" >> ${WORKDIR}/toolchain.cmake
	echo "set( WITH_SYSTEM_LIBURING ON )" >> ${WORKDIR}/toolchain.cmake
	echo "set( WITH_QATLIB OFF )" >> ${WORKDIR}/toolchain.cmake
	# echo "set( WITH_SYSTEM_ROCKSDB TRUE )" >> ${WORKDIR}/toolchain.cmake
}

do_compile:prepend() {
	export BUILD_DOC=1
}

do_install:prepend() {
	export BUILD_DOC=1
}

do_install:append () {
	sed -i -e 's:^#!/usr/bin/python$:&3:' \
		-e 's:${WORKDIR}.*python3:${bindir}/python3:' \
		${D}${bindir}/ceph ${D}${bindir}/ceph-crash \
		${D}${bindir}/cephfs-top \
		${D}${sbindir}/ceph-volume ${D}${sbindir}/ceph-volume-systemd \
		${D}${sbindir}/ceph-node-proxy
	find ${D} -name SOURCES.txt | xargs sed -i -e 's:${WORKDIR}::'
	# pip's PEP 610 metadata records the local file:// source path of each
	# python package it installs. Remove these introspection files so
	# do_package_qa doesn't trip on TMPDIR/buildpaths references — the
	# metadata is only consumed by `pip show --verbose` and similar, and
	# baking the build host path into the target image makes no sense.
	find ${D} -name 'direct_url.json' -o -name 'dependency_links.txt' | xargs --no-run-if-empty rm -f
	install -d ${D}${sysconfdir}/ceph
	install -m 644 ${UNPACKDIR}/ceph.conf ${D}${sysconfdir}/ceph/
	install -d ${D}${systemd_unitdir}
	mv ${D}${libexecdir}/ceph/ceph-osd-prestart.sh ${D}${libdir}/ceph
	mv ${D}${libexecdir}/ceph/ceph_common.sh ${D}${libdir}/ceph
	# WITH_FUSE is set to OFF, remove ceph-fuse related units
	rm ${D}${systemd_unitdir}/system/ceph-fuse.target ${D}${systemd_unitdir}/system/ceph-fuse@.service
}

do_install:append:class-target () {
	if ${@bb.utils.contains('DISTRO_FEATURES', 'systemd', 'true', 'false', d)}; then
		install -d ${D}${sysconfdir}/tmpfiles.d
		echo "d /var/lib/ceph/crash/posted 0755 root root - -" > ${D}${sysconfdir}/tmpfiles.d/ceph-placeholder.conf
	fi

	if ${@bb.utils.contains('DISTRO_FEATURES', 'sysvinit', 'true', 'false', d)}; then
		install -d ${D}${sysconfdir}/default/volatiles
		echo "d root root 0755 /var/lib/ceph/crash/posted none" > ${D}${sysconfdir}/default/volatiles/99_ceph-placeholder
	fi
}

pkg_postinst:${PN}() {
	if [ -z "$D" ] && [ -e ${sysconfdir}/init.d/populate-volatile.sh ] ; then
		${sysconfdir}/init.d/populate-volatile.sh update
	fi
}

FILES:${PN} += "\
		${libdir}/rados-classes/*.so.* \
		${libdir}/ceph/compressor/*.so \
		${libdir}/rados-classes/*.so \
		${libdir}/ceph/*.so \
		${libdir}/*.so \
		${libdir}/libcephsqlite.so \
"

FILES:${PN} += " \
    /etc/tmpfiles.d/ceph-placeholder.conf \
    /etc/default/volatiles/99_ceph-placeholder \
"

FILES:${PN}-dev = " \
    ${includedir} \
    ${libdir}/libcephfs.so \
    ${libdir}/librados*.so \
    ${libdir}/librbd.so \
    ${libdir}/librgw.so \
    ${libdir}/pkgconfig/cephfs.pc \
"

FILES:${PN}-python = "\
                ${PYTHON_SITEPACKAGES_DIR}/* \
"
RDEPENDS:${PN} += "\
		python3-core \
		python3-misc \
		python3-modules \
		python3-prettytable \
		${PN}-python \
		gawk \
		bash \
"
COMPATIBLE_HOST = "(x86_64).*"
PACKAGES += " \
	${PN}-python \
"
INSANE_SKIP:${PN}-python += "ldflags buildpaths"
INSANE_SKIP:${PN} += "dev-so"
INSANE_SKIP:${PN}-dbg += "buildpaths"
CCACHE_DISABLE = "1"

CVE_PRODUCT = "ceph ceph_storage ceph_storage_mon ceph_storage_osd"

CVE_STATUS[CVE-2017-7519] = "fixed-version: Fixed in 12.1.2, NVD tracks this as version-less vulnerability"
CVE_STATUS[CVE-2020-1700] = "fixed-version: Fixed in 15.1.1, NVD tracks this as version-less vulnerability"
