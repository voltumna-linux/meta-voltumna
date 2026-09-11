# claude: a vxn provision recipe, shipped in meta-virtualization and pre-
# positioned in dom0 at /usr/share/vxn/recipes/claude/. `vxn run claude` (and
# `axis run --policy vxn -- claude`) auto-provisions from this on first run --
# no user setup in an installed SDK.
#
# This is INSTRUCTIONS, not the software: it fetches the official Linux claude
# binary via Anthropic's installer at provision time; it does not bundle claude.
# In the same spirit as the layer's other third-party-fetch container recipes.
#
# Why the installer (not npm, not a host binary): `npm install -g` ships a
# dangling native-binary stub in a container build, and a host binary is
# Linux-host-only (AXIS runs on Linux/Windows/macOS). The installer fetches the
# LINUX native binary, so the image builds and runs regardless of host OS.
#
# NOTE (corp proxy): behind a TLS-intercepting proxy, the installer's HTTPS fetch
# needs the proxy CA. dom0 already trusts it (vxn-host-certs); injecting that CA
# into the provision chroot is a follow-up. Non-proxy environments work as-is.

FROM debian:stable-slim

# Runtime + install deps: glibc (base), CA certs (installer HTTPS + claude's API/
# OAuth TLS), git (claude shells out to it), curl (runs the installer).
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates git curl \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Fetch the official Linux native binary (installs under ~/.local); expose it on
# PATH and prove it runs (fails the build if the install is broken).
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
    && /usr/local/bin/claude --version

WORKDIR /work
ENTRYPOINT ["claude"]
