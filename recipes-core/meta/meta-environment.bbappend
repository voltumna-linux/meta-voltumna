create_sdk_files() {
	# Setup site file for external use
	toolchain_create_sdk_siteconfig ${SDK_OUTPUT}/${SDKPATH}/site-config-${REAL_MULTIMACH_TARGET_SYS}

	toolchain_create_sdk_env_script ${SDK_OUTPUT}/${SDKPATH}/environment-setup-${MACHINE}
	toolchain_create_sdk_env_script ${SDK_OUTPUT}/${SDKPATH}/environment-setup-${TUNE_PKGARCH}

	# Add version information
	toolchain_create_sdk_version ${SDK_OUTPUT}/${SDKPATH}/version-${REAL_MULTIMACH_TARGET_SYS}

	toolchain_create_post_relocate_script ${SDK_OUTPUT}/${SDKPATH}/post-relocate-setup.sh ${SDKPATH}
}

create_sdk_files:append() {
	# Create environment setup script.  Remember that $SDKTARGETSYSROOT should
	# only be expanded on the target at runtime.
	base_sbindir=${10:-${base_sbindir_nativesdk}}
	base_bindir=${9:-${base_bindir_nativesdk}}
	sbindir=${8:-${sbindir_nativesdk}}
	sdkpathnative=${7:-${SDKPATHNATIVE}}
	prefix=${6:-${prefix_nativesdk}}
	bindir=${5:-${bindir_nativesdk}}
	libdir=${4:-${libdir}}
	sysroot=${SDKPATHNATIVE}
	multimach_target_sys="x86_64-voltumnasdk-linux"
	script=${1:-${SDK_OUTPUT}/${SDKPATH}/environment-setup-x86_64}
	sdk_target_prefix="$multimach_target_sys-"
	rm -f $script
	touch $script

	echo '# Check for LD_LIBRARY_PATH being set, which can break SDK and generally is a bad practice' >> $script
	echo '# http://tldp.org/HOWTO/Program-Library-HOWTO/shared-libraries.html#AEN80' >> $script
	echo '# http://xahlee.info/UnixResource_dir/_/ldpath.html' >> $script
	echo '# Only disable this check if you are absolutely know what you are doing!' >> $script
	echo 'if [ ! -z "${LD_LIBRARY_PATH:-}" ]; then' >> $script
	echo "    echo \"Your environment is misconfigured, you probably need to 'unset LD_LIBRARY_PATH'\"" >> $script
	echo "    echo \"but please check why this was set in the first place and that it's safe to unset.\"" >> $script
	echo '    echo "The SDK will not operate correctly in most cases when LD_LIBRARY_PATH is set."' >> $script
	echo '    echo "For more references see:"' >> $script
	echo '    echo "  http://tldp.org/HOWTO/Program-Library-HOWTO/shared-libraries.html#AEN80"' >> $script
	echo '    echo "  http://xahlee.info/UnixResource_dir/_/ldpath.html"' >> $script
	echo '    return 1' >> $script
	echo 'fi' >> $script

	echo "${EXPORT_SDK_PS1}"\" x86_64:\$ \" >> $script
	echo 'export SDKTARGETSYSROOT='"$sysroot" >> $script
	echo 'if [ -z "$ORIGPATH" ]; then' >> $script
	echo '	export ORIGPATH="$PATH"' >> $script
	echo 'fi' >> $script
	echo "export PATH=$sdkpathnative$bindir:$sdkpathnative$sbindir:$sdkpathnative$base_bindir:$sdkpathnative$base_sbindir:$sdkpathnative$bindir/../${HOST_SYS}/bin"':"$ORIGPATH"' >> $script
	echo 'export PKG_CONFIG_SYSROOT_DIR=$SDKTARGETSYSROOT' >> $script
	echo 'export PKG_CONFIG_PATH=$SDKTARGETSYSROOT'"$libdir"'/pkgconfig:$SDKTARGETSYSROOT'"$prefix"'/share/pkgconfig' >> $script
	echo 'unset CONFIG_SITE' >> $script
	echo "export OECORE_NATIVE_SYSROOT=\"$sdkpathnative\"" >> $script
	echo 'export OECORE_TARGET_SYSROOT="$SDKTARGETSYSROOT"' >> $script
	echo "export OECORE_ACLOCAL_OPTS=\"-I $sdkpathnative/usr/share/aclocal\"" >> $script
	echo 'export OECORE_BASELIB="${baselib}"' >> $script
	echo 'export OECORE_TARGET_ARCH="x86_64"' >>$script
	echo 'export OECORE_TARGET_OS="linux"' >>$script

	echo 'unset command_not_found_handle' >> $script

	echo 'export CC="'${sdk_target_prefix}'gcc --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export CXX="'${sdk_target_prefix}'g++ --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export CPP="'${sdk_target_prefix}'gcc -E --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export AS="'${sdk_target_prefix}'as"' >> $script
	echo 'export LD="'${sdk_target_prefix}'ld --sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export GDB='${sdk_target_prefix}'gdb' >> $script
	echo 'export STRIP='${sdk_target_prefix}'strip' >> $script
	echo 'export RANLIB='${sdk_target_prefix}'ranlib' >> $script
	echo 'export OBJCOPY='${sdk_target_prefix}'objcopy' >> $script
	echo 'export OBJDUMP='${sdk_target_prefix}'objdump' >> $script
	echo 'export READELF='${sdk_target_prefix}'readelf' >> $script
	echo 'export AR='${sdk_target_prefix}'ar' >> $script
	echo 'export NM='${sdk_target_prefix}'nm' >> $script
	echo 'export M4=m4' >> $script
	echo 'export TARGET_PREFIX='${sdk_target_prefix} >> $script
	echo 'export CONFIGURE_FLAGS="--target='${multimach_target_sys}' --host='${multimach_target_sys}' --build=${SDK_ARCH}-linux --with-libtool-sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export CFLAGS="${TARGET_CFLAGS}"' >> $script
	echo 'export CXXFLAGS="${TARGET_CXXFLAGS}"' >> $script
	echo 'export LDFLAGS="${TARGET_LDFLAGS}"' >> $script
	echo 'export CPPFLAGS="${TARGET_CPPFLAGS}"' >> $script
	echo 'export KCFLAGS="--sysroot=$SDKTARGETSYSROOT"' >> $script
	echo 'export OECORE_DISTRO_VERSION="${DISTRO_VERSION}"' >> $script
	echo 'export OECORE_SDK_VERSION="${SDK_VERSION}"' >> $script
	echo 'export ARCH=x86' >> $script
	echo 'export CROSS_COMPILE='${sdk_target_prefix} >> $script
	echo 'export OECORE_TUNE_CCARGS=""' >> $script
	echo 'export RUST_TARGET_PATH="$SDKTARGETSYSROOT"'${libdir}/rustlib/${sdk_target_prefix}gnu >> $script

    cat >> $script <<EOF

if [ -d "\$OECORE_NATIVE_SYSROOT/environment-setup.d" ]; then
    for envfile in \$OECORE_NATIVE_SYSROOT/environment-setup.d/*.sh; do
	    . \$envfile
    done
fi
EOF
}
