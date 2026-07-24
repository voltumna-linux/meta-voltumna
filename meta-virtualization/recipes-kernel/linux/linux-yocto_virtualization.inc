FILESEXTRAPATHS:prepend := "${THISDIR}/linux-yocto:"

KERNEL_FEATURES:append = " ${@bb.utils.contains('DISTRO_FEATURES', 'kvm', ' features/kvm/qemu-kvm-enable.scc', '', d)}"

KERNEL_MODULE_AUTOLOAD += "nf_conntrack_ipv6 openvswitch"
KERNEL_MODULE_AUTOLOAD += "${@bb.utils.contains('DISTRO_FEATURES', 'kvm', 'kvm', '', d)}"

# aufs kernel support required for xen-image-minimal
KERNEL_FEATURES:append = "${@bb.utils.contains('DISTRO_FEATURES', 'aufs', ' features/aufs/aufs-enable.scc', '', d)}"

# Always add a local/layer fragment for easy debug and enabling of options
SRC_URI += "file://extra-configs.cfg"

# Inject the kcfg sysroot into the scc search path so compound .scc
# files (like container.scc) can resolve their include directives.
# Only needed for kernels that do NOT have a type=kmeta SRC_URI entry
# (i.e. no kernel-cache). The prefunc replaces this placeholder with
# a symlink to the kcfg sysroot only for non-kernel-cache kernels.
# For kernel-cache kernels the placeholder stays empty (harmless).
SRC_URI:append = " file://kcfg-search-path;type=kmeta;destsuffix=kcfg-sysroot"

python inject_kcfg_search_path() {
    import os, shutil

    # Skip if the kernel has its own kmeta (kernel-cache)
    src_uri = d.getVar('SRC_URI')
    # Check for type=kmeta entries other than our own kcfg-search-path
    for entry in src_uri.split():
        if 'type=kmeta' in entry and 'kcfg-search-path' not in entry:
            return

    unpackdir = d.getVar('UNPACKDIR')
    workdir = d.getVar('WORKDIR')
    search_dir = os.path.join(unpackdir, 'kcfg-sysroot')
    kcfg_sysroot = os.path.join(workdir, 'recipe-sysroot-native', 'kcfg')

    if os.path.isdir(kcfg_sysroot):
        if os.path.isdir(search_dir) and not os.path.islink(search_dir):
            shutil.rmtree(search_dir)
        if os.path.islink(search_dir) or not os.path.exists(search_dir):
            if os.path.islink(search_dir):
                os.unlink(search_dir)
            os.symlink(kcfg_sysroot, search_dir)
    else:
        bb.warn("kcfg sysroot not found at %s" % kcfg_sysroot)
}

do_kernel_metadata[prefuncs] += "inject_kcfg_search_path"

# Return the correct path for a kernel configuration fragment.
# Kernels with their own kernel-cache (type=kmeta in SRC_URI) already
# have fragments on spp's search path, so we use short paths that
# resolve directly. Kernels without kernel-cache need the sysroot-
# relative path (which requires the kcfg-search-path injection above).
def kernel_cache_feature(src_uri,feature):
    for entry in src_uri.split():
        if 'type=kmeta' in entry and 'kcfg-search-path' not in entry:
            return feature
    return "../../recipe-sysroot-native/kcfg/" + feature

def distro_cond_feature(feature_fragment,distro_feature,d):
    import bb
    feat = kernel_cache_feature(d.getVar('SRC_URI'),feature_fragment)
    return bb.utils.contains('DISTRO_FEATURES', distro_feature, ' ' + feat, ' ', d)

# kept as a reference if we go back to a dynamically calculated
# fragment dependency.
def kernel_meta_ver_depends(d):
    yocto_enabled = bb.data.inherits_class('kernel-yocto', d)
    if yocto_enabled:
        pv = oe.utils.trim_version(d.getVar('PV'), 2)
        return "yocto-cfg-fragments-%s-native:do_populate_sysroot" % pv
    else:
        return ""

KERNEL_CFG_DEPENDS ?= "${@['', 'yocto-cfg-fragments-${LINUX_MAJOR}.${LINUX_MINOR}-native:do_populate_sysroot'][(bb.data.inherits_class('kernel-yocto', d))]}"

KERNEL_CACHE_FEATURES ?= "${@kernel_cache_feature(d.getVar('SRC_URI'),'cfg/virtio.scc')} \
                          ${@kernel_cache_feature(d.getVar('SRC_URI'),'cfg/xt-checksum.scc')} \
                          ${@kernel_cache_feature(d.getVar('SRC_URI'),'cfg/vswitch.scc')} \
                          ${@kernel_cache_feature(d.getVar('SRC_URI'),'cfg/lxc.scc')} \
                          ${@kernel_cache_feature(d.getVar('SRC_URI'),'cfg/docker.scc')} \
                          ${@kernel_cache_feature(d.getVar('SRC_URI'),'cfg/cgroup-hugetlb.scc')} \
                          ${@kernel_cache_feature(d.getVar('SRC_URI'),'cfg/criu.scc')} \
                          "
KERNEL_FEATURES:append = " ${KERNEL_CACHE_FEATURES}"

# if kernel-yocto has been inherited (how we can check for configuration
# fragment merging suport at the moment, then add a dependency on the
# configuration fragment repository. This allows us to be sure that our
# features can be enabled via the fragments
do_kernel_metadata[depends] += "${KERNEL_CFG_DEPENDS}"

# if externalsrc is enabled, do_kernel_metadata dependency on
# yocto-cfg-fragments-native won't be run to populate
# recipe-sysroot-native/kcfg because do_patch is not run.  Manully add
# the dependency to do_kernel_configme for this special case
do_kernel_configme[depends] += "${@['', d.getVar('PN') + ':do_kernel_metadata'][(bb.data.inherits_class('externalsrc', d))]}"

# xen kernel support
# SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'xen', ' file://xen.scc', '', d)}"
KERNEL_FEATURES:append = "${@distro_cond_feature('cfg/xen.scc', 'xen', d )}"

# k8s and k3s kernel support
# SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'k8s', ' file://kubernetes.scc', '', d)}"
# SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'k3s', ' file://kubernetes.scc', '', d)}"
KERNEL_FEATURES:append = "${@distro_cond_feature('cfg/kubernetes.scc', 'k8s', d )}"
KERNEL_FEATURES:append = "${@distro_cond_feature('cfg/kubernetes.scc', 'k3s', d )}"

# selinux
KERNEL_FEATURES:append = "${@distro_cond_feature('cgl/features/selinux/selinux.cfg', 'selinux', d )}"

# vcontainer
KERNEL_FEATURES:append = "${@distro_cond_feature('cfg/container.scc', 'vcontainer', d)}"

# vxn: Xen PV guest support for vcontainer-on-Xen
SRC_URI += "${@bb.utils.contains('DISTRO_FEATURES', 'vxn', ' file://vxn.cfg', '', d)}"
