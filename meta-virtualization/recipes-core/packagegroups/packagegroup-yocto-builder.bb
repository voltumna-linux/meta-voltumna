SUMMARY = "Packages for a self-hosting Yocto build container"
DESCRIPTION = "Build tools required to compile the Yocto Project. \
    Based on packagegroup-self-hosted but without x11/opengl requirements."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

PACKAGE_ARCH = "${TUNE_PKGARCH}"

inherit packagegroup

inherit features_check
REQUIRED_DISTRO_FEATURES ?= "systemd"

PACKAGES = "\
    packagegroup-yocto-builder \
    packagegroup-yocto-builder-base \
    packagegroup-yocto-builder-toolchain \
    packagegroup-yocto-builder-extras \
"

RDEPENDS:packagegroup-yocto-builder = "\
    packagegroup-yocto-builder-base \
    packagegroup-yocto-builder-toolchain \
    packagegroup-yocto-builder-extras \
"

# Layer 1: systemd core + container basics
RDEPENDS:packagegroup-yocto-builder-base = "\
    base-files \
    base-passwd \
    netbase \
    systemd \
    dbus \
    bash \
    coreutils \
    packagegroup-core-base-utils \
    packagegroup-core-ssh-openssh \
    container-systemd-config \
    builder-container-config \
    iproute2 \
    iputils-ping \
"

# Layer 2: compiler toolchain + dev tools
RDEPENDS:packagegroup-yocto-builder-toolchain = "\
    autoconf \
    automake \
    binutils \
    binutils-symlinks \
    ccache \
    cpp \
    cpp-symlinks \
    gcc \
    gcc-symlinks \
    g++ \
    g++-symlinks \
    make \
    libtool \
    pkgconfig \
    ldd \
    less \
    file \
    findutils \
    quilt \
    sed \
    libstdc++ \
    libstdc++-dev \
    diffutils \
    git \
    git-perltools \
    python3 \
    python3-modules \
    perl \
    perl-modules \
    perl-dev \
    perl-misc \
    perl-pod \
    perl-module-re \
    perl-module-text-wrap \
    patch \
    gawk \
    grep \
    tar \
    gzip \
    bzip2 \
    xz \
    zstd \
    rpcsvc-proto \
    ${@bb.utils.contains('TCLIBC', 'glibc', 'glibc-utils', '', d)} \
"

# Layer 3: Yocto-specific tools + utilities
RDEPENDS:packagegroup-yocto-builder-extras = "\
    python3-jinja2 \
    python3-pexpect \
    python3-pip \
    python3-git \
    lz4 \
    chrpath \
    diffstat \
    texinfo \
    socat \
    cpio \
    unzip \
    zip \
    wget \
    curl \
    tmux \
    screen \
    sudo \
    ${@bb.utils.contains('TCLIBC', 'glibc', 'pseudo', '', d)} \
    gdb \
    rsync \
    strace \
    openssl \
    openssh-scp \
    openssh-sftp-server \
    ${@bb.utils.contains('TCLIBC', 'glibc', 'glibc-localedata-en-us glibc-gconv-ibm850', '', d)} \
    rpm \
    opkg \
    opkg-utils \
    elfutils \
    readline \
    ncurses \
    ncurses-terminfo-base \
    subversion \
"
