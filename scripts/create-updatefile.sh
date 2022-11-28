#!/bin/sh

if [ "$USER" != "root" ]; then
	echo "The script must be executed as root"
	exit
fi

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 FROM.os.tar.xz TO.os.tar.xz"
	exit 1
fi

ORIGDIR=$(pwd)
TEMPDIR=$(mktemp -d)

cleanup() {
	rm -fr $INCRUPDATE.sh $FULLUPDATE.sh  $TEMPDIR
}

cleanup_exit() {
	cleanup
	exit 1
}
	
trap cleanup_exit 1 2 3 6

tar Jxf "$1" -C $TEMPDIR
FROMVER=$(sed -ne 's,VERSION_ID=\(.*\),\1,p' $TEMPDIR/*/lib/os-release)

tar Jxf "$2" -C $TEMPDIR
TOVER=$(sed -ne 's,VERSION_ID=\(.*\),\1,p' $TEMPDIR/*/lib/os-release | grep -v ${FROMVER}$)

FROMBASEIMAGE=$(echo $(basename $1) | sed "s/\(.*\)-${FROMVER}.os.tar.xz/\1/")
TOBASEIMAGE=$(echo $(basename $2) | sed "s/\(.*\)-${TOVER}.os.tar.xz/\1/")

if [ "${FROMBASEIMAGE}" != "${TOBASEIMAGE}" ]; then
	cleanup
	echo "Images are of different type!"
	exit 1
fi

mkdir ${TEMPDIR}/empty

INCRUPDATE="$FROMBASEIMAGE-$FROMVER-$TOVER"
FULLUPDATE="$TOBASEIMAGE--$TOVER"

rm -f $INCRUPDATE $FULLUPDATE

# To track change-set use --info=stats3 and search for "built hash table"

cd $TEMPDIR
rsync -azchHEADXK --delete --timeout=60 --only-write-batch=$ORIGDIR/$INCRUPDATE $TOBASEIMAGE-$TOVER/ $FROMBASEIMAGE-$FROMVER/
rsync -azchHEADXK --delete --timeout=60 --only-write-batch=$ORIGDIR/$FULLUPDATE $TOBASEIMAGE-$TOVER/ empty/
cd $ORIGDIR

if [ -n "${SUDO_USER}" ]; then
	chown ${SUDO_USER}: ${INCRUPDATE} ${FULLUPDATE}
fi

chmod 644 ${INCRUPDATE} ${FULLUPDATE}

mv $INCRUPDATE $INCRUPDATE.incr.upd
mv $FULLUPDATE $FULLUPDATE.full.upd

cleanup
