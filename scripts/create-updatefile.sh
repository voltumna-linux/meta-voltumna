#!/bin/sh

if [ "$USER" != "root" ]; then
	echo "The script must be executed as root"
	exit
fi

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 FROM.tar TO.tar"
	exit 1
fi

ORIGDIR=$(pwd)
TEMPDIR=$(mktemp -d)

cleanup() {
	rm -fr $UPDATE.sh $TEMPDIR ${TO}.sh
}

cleanup_exit() {
	cleanup
	exit 1
}

trap cleanup_exit 1 2 3 6

tar xf "$1" -C $TEMPDIR
FROM=$(sed -ne 's,VERSION_ID=\(.*\),\1,p' $TEMPDIR/*/lib/os-release)

tar xf "$2" -C $TEMPDIR
TO=$(sed -ne 's,VERSION_ID=\(.*\),\1,p' $TEMPDIR/*/lib/os-release | grep -v ${FROM}$)

mkdir ${TEMPDIR}/empty

UPDATE="$FROM-$TO"

if [ -f "${UPDATE}" ]; then
	cleanup
	echo "Update file already exist!"
	exit 1
fi

cd $TEMPDIR
rsync -azchHEADX --delete --only-write-batch=$ORIGDIR/$UPDATE *$TO/ *$FROM/
rsync -azchHEADX --delete --only-write-batch=$ORIGDIR/$TO *$TO/ empty/
cd $ORIGDIR

if [ -n "${SUDO_USER}" ]; then
	chown ${SUDO_USER}: ${UPDATE} ${TO}
fi

mv $UPDATE $UPDATE.incr.upd
mv $TO $TO.full.upd

cleanup
