#!/bin/sh
# Based on https://github.com/valkey-io/valkey-container/blob/mainline/docker-entrypoint.sh
# SPDX-License-Identifier: BSD-3-Clause
set -e

# first arg is `-f` or `--some-option`
# or first arg is `something.conf`
if [ "${1#-}" != "$1" ] || [ "${1%.conf}" != "$1" ]; then
    set -- valkey-server "$@"
fi

# set an appropriate umask (if one isn't set already)
um="$(umask)"
if [ "$um" = '0022' ]; then
    umask 0077
fi

exec "$@"
