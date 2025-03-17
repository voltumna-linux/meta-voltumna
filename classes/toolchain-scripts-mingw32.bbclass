# Based off of the oe-core meta/classes/toolchain-scripts.bbclass version
toolchain_create_sdk_env_script:sdkmingw32 () {
	# Create environment setup script
	sdkpathnative=${7:-${SDKPATHNATIVE}}
	prefix=${6:-${prefix_nativesdk}}
	bindir=${5:-${bindir_nativesdk}}
	libdir=${4:-${libdir}}
	sysroot=${3:-${SDKTARGETSYSROOT}}
	multimach_target_sys=${2:-${REAL_MULTIMACH_TARGET_SYS}}
	script=${1:-${SDK_OUTPUT}/${SDKPATH}/environment-setup-$multimach_target_sys}.bat
	rm -f $script
	touch $script
	# Be sure to use the 'short' path, so we can have deeper directories.
	echo 'set SDKROOT=%~sdp0%' >> $script
	echo 'IF %SDKROOT:~-1%==\ set SDKROOT=%SDKROOT:~0,-1%' >> $script

	# Convert to mingw32 subpaths
	sysroot='%SDKROOT%'${sysroot##${SDKPATH}}
	sdkpathnative='%SDKROOT%'${sdkpathnative##${SDKPATH}}

	echo 'set SDKTARGETSYSROOT='"$sysroot" >> $script
	EXTRAPATH=""
	for i in ${CANADIANEXTRAOS}; do
		EXTRAPATH="$EXTRAPATH;$sdkpathnative$bindir/${TARGET_ARCH}${TARGET_VENDOR}-$i"
	done
	echo "set PATH=$sdkpathnative$bindir;$sdkpathnative$bindir/../${HOST_SYS}/bin;$sdkpathnative$bindir/${TARGET_SYS}"$EXTRAPATH';%PATH%' >> $script
	echo 'set PKG_CONFIG_SYSROOT_DIR=%SDKTARGETSYSROOT%' >> $script
	echo 'set PKG_CONFIG_PATH=%SDKTARGETSYSROOT%'"$libdir"'/pkgconfig' >> $script
	echo 'set CONFIG_SITE=%SDKROOT%/site-config-'"${multimach_target_sys}" >> $script
	echo "set OECORE_NATIVE_SYSROOT=$sdkpathnative" >> $script
	echo 'set OECORE_TARGET_SYSROOT=%SDKTARGETSYSROOT%' >> $script
	echo "set OECORE_ACLOCAL_OPTS=-I $sdkpathnative/usr/share/aclocal" >> $script
	echo 'set OECORE_BASELIB=${baselib}' >> $script
	echo 'set OECORE_TARGET_ARCH=${TARGET_ARCH}' >> $script
	echo 'set OECORE_TARGET_OS=${TARGET_OS}' >> $script

	toolchain_shared_env_script

	# Change unix '/' to Win32 '\'
	sed -e 's,/,\\,g' -i $script

	# set has some annoying properties:
	# 1) If it is successful %ERRORLEVEL% is unchanged (as opposed to being set
	#	 to 0 to indicate success)
	# 2) Making an assignment like "set A=" is considered an error and sets
	#	 %ERRORLEVEL% to 1.
	#
	# Practically, this means that if any of the set calls make an empty
	# assignment that error will be propagated. To prevent this, a command is
	# run to ensure that the "exit code" of this script is 0
	echo "@%COMSPEC% /C exit 0 > NUL" >> $script

	# Make the file windows friendly...
	awk 'sub("$", "\r")' $script > $script.new
	mv $script.new $script
}

toolchain_shared_env_script:sdkmingw32 () {
	echo 'set CC=${TARGET_PREFIX}gcc ${TARGET_CC_ARCH} --sysroot=%SDKTARGETSYSROOT%' >> $script
	echo 'set CXX=${TARGET_PREFIX}g++ ${TARGET_CC_ARCH} --sysroot=%SDKTARGETSYSROOT%' >> $script
	echo 'set CPP=${TARGET_PREFIX}gcc -E ${TARGET_CC_ARCH} --sysroot=%SDKTARGETSYSROOT%' >> $script
	echo 'set AS=${TARGET_PREFIX}as ${TARGET_AS_ARCH}' >> $script
	echo 'set LD=${TARGET_PREFIX}ld ${TARGET_LD_ARCH} --sysroot=%SDKTARGETSYSROOT%' >> $script
	echo 'set GDB=${TARGET_PREFIX}gdb' >> $script
	echo 'set STRIP=${TARGET_PREFIX}strip' >> $script
	echo 'set RANLIB=${TARGET_PREFIX}ranlib' >> $script
	echo 'set OBJCOPY=${TARGET_PREFIX}objcopy' >> $script
	echo 'set OBJDUMP=${TARGET_PREFIX}objdump' >> $script
	echo 'set AR=${TARGET_PREFIX}ar' >> $script
	echo 'set NM=${TARGET_PREFIX}nm' >> $script
	echo 'set M4=m4' >> $script
	echo 'set TARGET_PREFIX=${TARGET_PREFIX}' >> $script
	echo 'set CONFIGURE_FLAGS=--target=${TARGET_SYS} --host=${TARGET_SYS} --build=${SDK_ARCH}-linux --with-libtool-sysroot=%SDKTARGETSYSROOT%' >> $script
	echo 'set CFLAGS=${TARGET_CFLAGS}' >> $script
	echo 'set CXXFLAGS=${TARGET_CXXFLAGS}' >> $script
	echo 'set LDFLAGS=${TARGET_LDFLAGS}' >> $script
	echo 'set CPPFLAGS=${TARGET_CPPFLAGS}' >> $script
	echo 'set KCFLAGS=--sysroot=%SDKTARGETSYSROOT%' >> $script
	echo 'set OECORE_DISTRO_VERSION=${DISTRO_VERSION}' >> $script
	echo 'set OECORE_SDK_VERSION=${SDK_VERSION}' >> $script
	echo 'set ARCH=${ARCH}' >> $script
	echo 'set CROSS_COMPILE=${TARGET_PREFIX}' >> $script

	cat >> $script <<EOF

@REM Append environment subscripts

@IF EXIST %OECORE_TARGET_SYSROOT%\\environment-setup.d (
   FOR %%x IN (%OECORE_TARGET_SYSROOT%\\environment-setup.d\\*.bat) DO call "%%x"
)

@IF EXIST %OECORE_NATIVE_SYSROOT%\\environment-setup.d (
   FOR %%x IN (%OECORE_NATIVE_SYSROOT%\\environment-setup.d\\*.bat) DO call "%%x"
)
EOF
}

toolchain_create_sdk_siteconfig:append:sdkmingw32 () {
        # Make the file windows friendly...
        awk 'sub("$", "\r")' $siteconfig > $siteconfig.new
        mv $siteconfig.new $siteconfig
}

toolchain_create_sdk_version:append:sdkmingw32 () {
        # Make the file windows friendly...
        awk 'sub("$", "\r")' $versionfile > $versionfile.new
        mv $versionfile.new $versionfile
}
