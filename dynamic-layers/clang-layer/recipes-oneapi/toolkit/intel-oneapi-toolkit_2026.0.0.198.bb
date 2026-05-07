SUMMARY = "Intel® oneAPI Toolkit (2026.0) - unified Base + HPC toolkit"
DESCRIPTION = "The Intel® oneAPI Toolkit unifies the former Base and HPC \
toolkits into a single bundle. It ships the DPC++/C++ compiler (icx, \
icpx, dpcpp), Fortran compiler (ifx), DPC++ Compatibility Tool, Intel® \
Distribution for GDB*, oneAPI DPC++ Library (oneDPL), oneAPI Threading \
Building Blocks (oneTBB), oneAPI Math Kernel Library (oneMKL), oneAPI \
Deep Neural Network Library (oneDNN), oneCCL, Intel® IPP, Intel® \
Cryptography Primitives Library, and VTune Profiler. \
\
This recipe consumes the upstream offline self-extracting installer \
(intel-oneapi-toolkit-${PV}_offline.sh) and unpacks it into the target \
rootfs under /opt/intel/oneapi via Intel's silent installer. Each \
component is split into its own sub-package (intel-oneapi-toolkit-\
{compiler,runtime,mkl,tbb,dpl,debugger,ipp,ccl,vtune,onednn,common,\
licensing}). \
\
Note: oneDAL is no longer included by Intel and must be installed \
separately."

HOMEPAGE = "https://www.intel.com/content/www/us/en/developer/tools/oneapi/oneapi-toolkit-download.html"

LICENSE = "EULA"
LIC_FILES_CHKSUM = "\
    file://license.txt;md5=cff4e57efd53801fcdfcb4c8aead1245 \
"

# Self-extracting installer; treat as opaque blob (no auto-unpack).
SRC_URI = " \
    https://registrationcenter-download.intel.com/akdlm/IRC_NAS/71180075-e4e3-4c6f-bbbb-19017ed0cf7d/intel-oneapi-toolkit-${PV}_offline.sh;unpack=0;name=installer \
    file://license.txt \
"
SRC_URI[installer.sha256sum] = "155a52896bd24239ddc733f487eccb2af5cad9957eed1e2bfe60ce1453694e5b"

S = "${UNPACKDIR}"

inherit bin_package

B = "${WORKDIR}/build"

INHIBIT_PACKAGE_DEBUG_SPLIT = "1"
INHIBIT_SYSROOT_STRIP = "1"
SKIP_FILEDEPS:${PN} = "1"
SKIP_FILEDEPS:${PN}-runtime = "1"
SKIP_FILEDEPS:${PN}-compiler = "1"
SKIP_FILEDEPS:${PN}-common = "1"
SKIP_FILEDEPS:${PN}-licensing = "1"
SKIP_FILEDEPS:${PN}-mkl = "1"
SKIP_FILEDEPS:${PN}-tbb = "1"
SKIP_FILEDEPS:${PN}-dpl = "1"
SKIP_FILEDEPS:${PN}-debugger = "1"
SKIP_FILEDEPS:${PN}-ipp = "1"
SKIP_FILEDEPS:${PN}-ccl = "1"
SKIP_FILEDEPS:${PN}-vtune = "1"
SKIP_FILEDEPS:${PN}-onednn = "1"

ONEAPI_INSANE = "textrel dev-so dev-elf ldflags already-stripped staticdev rpaths arch useless-rpaths file-rdeps libdir buildpaths host-user-contaminated installed-vs-shipped 32bit-time"
INSANE_SKIP:${PN} += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-runtime += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-compiler += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-common += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-licensing += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-mkl += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-tbb += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-dpl += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-debugger += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-ipp += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-ccl += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-vtune += "${ONEAPI_INSANE}"
INSANE_SKIP:${PN}-onednn += "${ONEAPI_INSANE}"

FILES_SOLIBSDEV = ""
EXCLUDE_FROM_SHLIBS = "1"
PACKAGE_DEBUG_FLAGS = ""

# Versions of components used in do_install runtime registration.
# (Component sub-directories are matched by name in FILES, so per-component
# version variables are not needed.)
COMPILERMAINVER = "2026.0"

ONEAPI_INSTALLER = "${S}/intel-oneapi-toolkit-${PV}_offline.sh"
ONEAPI_STAGE     = "${B}/oneapi-staging"

# do_unpack_vendor runs without pseudo. ${B} (B = ${WORKDIR}/build) is a
# sibling of ${T}, so the installer's cleanup never reaches the fifo.
do_unpack_vendor() {
    rm -rf "${ONEAPI_STAGE}"
    install -d "${ONEAPI_STAGE}/opt/intel/oneapi"

    # WARNING: never reference ${HOME} or ${TMPDIR} as bitbake-expanded
    # variables inside this function — bitbake expands them at parse
    # time to the build host's real values, and a later `rm -rf` would
    # nuke the developer's home directory. Use plain shell locals only.
    oneapi_home="${B}/oneapi-installer-home"
    oneapi_tmp="${B}/oneapi-installer-tmp"
    oneapi_extract="${B}/oneapi-installer-extract"
    rm -rf "$oneapi_home" "$oneapi_tmp" "$oneapi_extract"
    install -d "$oneapi_home" "$oneapi_tmp" "$oneapi_extract"

    # The installer needs a writable HOME and TMPDIR.
    export HOME="$oneapi_home"
    export TMPDIR="$oneapi_tmp"

    cd "$oneapi_extract"

    bash ${ONEAPI_INSTALLER} \
        --extract-folder "$oneapi_extract" \
        --remove-extracted-files no \
        -a --silent --eula accept \
        --install-dir "${ONEAPI_STAGE}/opt/intel/oneapi" \
        --log-dir "$oneapi_tmp" \
        --intel-sw-improvement-program-consent decline

    # Free the makeself extraction tree once the install completed.
    rm -rf "$oneapi_extract" "$oneapi_home" "$oneapi_tmp"

    # Rewrite any absolute build-time paths the installer baked into
    # generated wrapper scripts so the on-target tree is self-contained.
    find "${ONEAPI_STAGE}/opt/intel/oneapi" -type f \
        \( -name '*.sh' -o -name '*.cfg' -o -name 'modulefiles-setup.sh' \) \
        -exec sed -i "s|${ONEAPI_STAGE}/opt/intel/oneapi|/opt/intel/oneapi|g" {} +
}
do_unpack_vendor[network] = "0"
do_unpack_vendor[cleandirs] = "${B}"
addtask unpack_vendor after do_patch before do_install

do_install() {
    install -d ${D}
    cp -a ${ONEAPI_STAGE}/. ${D}/

    # The vendor installer in do_unpack_vendor runs outside pseudo, so
    # all staged files inherit the build host's uid/gid. Reset ownership
    # to root:root under pseudo to avoid host-contamination QA failures
    # ("getpwuid(): uid not found ...") in do_package.
    chown -R 0:0 ${D}

    # Drop the installer's transient log directory (build-time noise).
    rm -rf ${D}/opt/intel/oneapi/logs

    # Auto-register the Intel CPU OpenCL runtime as an ICD.
    install -d ${D}${sysconfdir}/OpenCL/vendors
    cpu_icd="/opt/intel/oneapi/compiler/${COMPILERMAINVER}/lib/libintelocl.so"
    if [ -e "${D}${cpu_icd}" ]; then
        echo "${cpu_icd}" > ${D}${sysconfdir}/OpenCL/vendors/intel-cpu.icd
    fi

    # libxml2.so.2 SONAME compat shim (oe-core ships libxml2 3.x = .so.16).
    install -d ${D}${libdir}
    if [ ! -e ${D}${libdir}/libxml2.so.2 ]; then
        ln -s libxml2.so.16 ${D}${libdir}/libxml2.so.2
    fi
}

SYSROOT_DIRS += "/opt"

# Sub-packages. Order matters in PACKAGES — first-match wins for FILES
# patterns, so put specific component packages before the catch-all ${PN}.
PACKAGES =+ " \
    ${PN}-runtime \
    ${PN}-compiler \
    ${PN}-mkl \
    ${PN}-tbb \
    ${PN}-dpl \
    ${PN}-debugger \
    ${PN}-ipp \
    ${PN}-ccl \
    ${PN}-vtune \
    ${PN}-onednn \
    ${PN}-licensing \
    ${PN}-common \
"

FILES:${PN}-licensing = "/opt/intel/oneapi/licensing"
FILES:${PN}-common = " \
    /opt/intel/oneapi/setvars.sh \
    /opt/intel/oneapi/modulefiles-setup.sh \
    /opt/intel/oneapi/support.txt \
    /opt/intel/oneapi/common \
    /opt/intel/oneapi/2026.0 \
    /opt/intel/oneapi/oneapi-toolkit \
"
FILES:${PN}-onednn = "/opt/intel/oneapi/dnnl"
FILES:${PN}-tbb = "/opt/intel/oneapi/tbb"
FILES:${PN}-dpl = "/opt/intel/oneapi/dpl"
FILES:${PN}-mkl = "/opt/intel/oneapi/mkl"
FILES:${PN}-debugger = "/opt/intel/oneapi/debugger"
FILES:${PN}-ipp = " \
    /opt/intel/oneapi/ipp \
    /opt/intel/oneapi/ippcp \
"
FILES:${PN}-ccl = "/opt/intel/oneapi/ccl"
FILES:${PN}-vtune = "/opt/intel/oneapi/vtune"
FILES:${PN}-compiler = " \
    /opt/intel/oneapi/compiler \
    /opt/intel/oneapi/dev-utilities \
    /opt/intel/oneapi/tcm \
    /opt/intel/oneapi/umf \
    /opt/intel/oneapi/mpi \
"
FILES:${PN}-runtime = " \
    ${sysconfdir}/OpenCL/vendors/intel-cpu.icd \
    ${libdir}/libxml2.so.2 \
"

# Inter-package dependencies.
RDEPENDS:${PN}-compiler  += "${PN}-runtime ${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-mkl       += "${PN}-runtime ${PN}-common ${PN}-licensing ${PN}-tbb"
RDEPENDS:${PN}-tbb       += "${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-dpl       += "${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-debugger  += "${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-ipp       += "${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-ccl       += "${PN}-runtime ${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-vtune     += "${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-onednn    += "${PN}-common ${PN}-licensing"
RDEPENDS:${PN}-runtime   += "virtual-opencl-icd zlib level-zero-loader bash tcsh libxml2 ${PN}-common ${PN}-licensing"

# Top-level meta package pulls in the full bundle.
RDEPENDS:${PN} = " \
    ${PN}-compiler \
    ${PN}-runtime \
    ${PN}-mkl \
    ${PN}-tbb \
    ${PN}-dpl \
    ${PN}-debugger \
    ${PN}-ipp \
    ${PN}-ccl \
    ${PN}-vtune \
    ${PN}-onednn \
    ${PN}-common \
    ${PN}-licensing \
"

# This bundle is amd64-only.
COMPATIBLE_HOST = "x86_64.*-linux"
