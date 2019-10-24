#!/usr/bin/env bash

set -e
# set -x

WORKDIR=`pwd`

. /etc/os-release
curl -s http://127.0.0.1/api/firmware/publish/running -d"${VARIANT_ID}-${MACHINE}-${VERSION_ID}"

. /.osdir/default/lib/os-release
curl -s http://127.0.0.1/api/firmware/publish/default -d"${VARIANT_ID}-${MACHINE}-${VERSION_ID}"

RELEASES=""
for release in $(ls -d /.osdir/*)
do
	. $release/lib/os-release
	RELEASES="${RELEASES}${VARIANT_ID}-${MACHINE}-${VERSION_ID}\n"
done
curl -s http://127.0.0.1/api/firmware/publish/availables -d"$(echo -e $RELEASES | grep -v ^$ | sort | uniq)"
