SKIP_META_VIRT_SANITY_CHECK ?= "1"

addhandler virt_bbappend_distrocheck
virt_bbappend_distrocheck[eventmask] = "bb.event.SanityCheck"
python virt_bbappend_distrocheck() {
    skip_check = e.data.getVar('SKIP_META_VIRT_SANITY_CHECK') == "1"
    if 'virtualization' not in e.data.getVar('DISTRO_FEATURES').split() and not skip_check:
        bb.warn("You have included the meta-virtualization layer, but \
'virtualization' has not been enabled in your DISTRO_FEATURES. Some bbappend files \
may not take effect. See the meta-virtualization README for details on enabling \
virtualization support.")
}

# Check for vcontainer requirements when vcontainer distro feature is enabled
addhandler vcontainer_sanity_check
vcontainer_sanity_check[eventmask] = "bb.event.SanityCheck"
python vcontainer_sanity_check() {
    # Only run for main multiconfig (avoid duplicate messages)
    mc = e.data.getVar('BB_CURRENT_MC') or ''
    if mc != '':
        return

    skip_check = e.data.getVar('SKIP_META_VIRT_SANITY_CHECK') == "1"
    if skip_check:
        return

    distro_features = (e.data.getVar('DISTRO_FEATURES') or "").split()

    if 'vcontainer' not in distro_features:
        return

    # Check for required BBMULTICONFIG
    bbmulticonfig = e.data.getVar('BBMULTICONFIG') or ""
    required_mcs = ['vruntime-aarch64', 'vruntime-x86-64']
    missing_mcs = [mc for mc in required_mcs if mc not in bbmulticonfig]

    if missing_mcs:
        bb.warn("vcontainer: BBMULTICONFIG is missing required multiconfigs: %s\n"
                "Add to local.conf:\n"
                "  BBMULTICONFIG = \"vruntime-aarch64 vruntime-x86-64\"\n"
                "This is required for building vdkr/vpdmn cross-architecture container tools."
                % ', '.join(missing_mcs))

    # Informational message about vcontainer setup
    bb.note("vcontainer enabled. Required settings:\n"
            "  DISTRO_FEATURES: vcontainer (detected)\n"
            "  BBMULTICONFIG: vruntime-aarch64 vruntime-x86-64 %s\n"
            "Optional settings:\n"
            "  CONTAINER_PROFILE: docker|podman (default: docker)\n"
            "  CONTAINER_REGISTRY_URL: registry address for container-registry feature\n"
            "  BUNDLED_CONTAINERS: containers to bundle into images"
            % ("(OK)" if not missing_mcs else "(MISSING)"))
}
