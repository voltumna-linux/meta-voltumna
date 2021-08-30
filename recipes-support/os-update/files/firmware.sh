#!/usr/bin/env bash

set -e
# set -x

WORKDIR=`pwd`
URL=http://127.0.0.1/api/firmware/publish

. /etc/os-release
curl -k -s ${URL}/running -d"${VARIANT_ID}-${MACHINE}-${VERSION_ID}"

. /.osdir/default/lib/os-release
curl -k -s ${URL}/default -d"${VARIANT_ID}-${MACHINE}-${VERSION_ID}"

RELEASES=""
for release in $(ls -d /.osdir/*)
do
	. $release/lib/os-release
	RELEASES="${RELEASES}${VARIANT_ID}-${MACHINE}-${VERSION_ID}\n"
done
curl -k -s ${URL}/availables -d"$(echo -e $RELEASES | grep -v ^$ | sort | uniq)"

os-netconfig | curl -k -s ${URL}/netconfig -d @-
