#!/bin/sh

mkdir -p /run/rnm-dpdk
touch /run/rnm-dpdk/rnm.conf

. /etc/rnm.conf
export $(cat /sys/class/net/$RNM_NETIF/device/uevent)
echo RNM_NETIF=$PCI_SLOT_NAME >> /run/rnm-dpdk/rnm.conf

NAME=$(hostname)-rnm
DNSREPLY=$(resolvectl query $NAME)
if [ "$?" -eq 0 ]; then
	ADDRESS=$(echo "$DNSREPLY" | sed -n "s,$NAME: \([0-9.]*\) .*,\1,p")
	LASTOCTECT=$(echo $ADDRESS | cut -d. -f4)
	echo CLIENTID="-- --client-id $LASTOCTECT" >> /run/rnm-dpdk/rnm.conf
fi


