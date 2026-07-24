#!/bin/bash
# builder-entry.sh - Container entrypoint for Yocto builder
# Creates a 'builder' user matching the /workdir owner's UID/GID,
# then exec's /sbin/init (systemd).
#
# Usage:
#   docker run --privileged -v /home/user/yocto:/workdir builder-image
#   docker run --privileged -e BUILDER_UID=1000 -e BUILDER_GID=1000 builder-image

WORKDIR="/workdir"
DEFAULT_UID=1000
DEFAULT_GID=1000

# Determine UID/GID
if [ -n "$BUILDER_UID" ] && [ -n "$BUILDER_GID" ]; then
    TARGET_UID="$BUILDER_UID"
    TARGET_GID="$BUILDER_GID"
elif [ -d "$WORKDIR" ] && [ "$(stat -c %u "$WORKDIR")" != "0" ]; then
    TARGET_UID=$(stat -c %u "$WORKDIR")
    TARGET_GID=$(stat -c %g "$WORKDIR")
else
    TARGET_UID=$DEFAULT_UID
    TARGET_GID=$DEFAULT_GID
fi

# Refuse UID/GID 0 (root)
[ "$TARGET_UID" = "0" ] && TARGET_UID=$DEFAULT_UID
[ "$TARGET_GID" = "0" ] && TARGET_GID=$DEFAULT_GID

# Create group and user if they don't exist
if ! getent group builder >/dev/null 2>&1; then
    groupadd -g "$TARGET_GID" builder 2>/dev/null || groupadd builder
fi
if ! getent passwd builder >/dev/null 2>&1; then
    useradd -m -u "$TARGET_UID" -g builder -s /bin/bash builder
fi

# Ensure /workdir is accessible
[ -d "$WORKDIR" ] && chown builder:builder "$WORKDIR"

# Grant passwordless sudo
if [ -d /etc/sudoers.d ]; then
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
    chmod 0440 /etc/sudoers.d/builder
fi

# Hand off to systemd
exec /sbin/init "$@"
