#!/bin/sh

mkdir -p /run/rnm-dpdk
touch /run/rnm-dpdk/rnm.conf

. /etc/rnm.conf
. /sys/class/net/$RNM_NETIF/device/uevent
echo RNM_NETIF=$PCI_SLOT_NAME > /run/rnm-dpdk/rnm.conf

NAME=$(hostname)-rnm
DNSREPLY=$(resolvectl query --legend=no $NAME 2>/dev/null)
if [ "$?" -eq 0 ]; then
	ADDRESS=$(echo $DNSREPLY | sed -n "s,$NAME: \([0-9\.]*\) .*,\1,p")
	LASTOCTECT=$(echo $ADDRESS | cut -d. -f4)
	echo CLIENTID=$LASTOCTECT >> /run/rnm-dpdk/rnm.conf
else
	echo CLIENTID=0 >> /run/rnm-dpdk/rnm.conf
fi
echo RNM_LCORE=$RNM_LCORE >> /run/rnm-dpdk/rnm.conf
if [ -n "$RNM_DEVARGS" ]; then
	echo RNM_DEVARGS=,$RNM_DEVARGS >> /run/rnm-dpdk/rnm.conf
fi

/usr/bin/dpdk-devbind.py --bind=vfio-pci \
	$(basename -a /sys/bus/pci/devices/$PCI_SLOT_NAME/iommu_group/devices/${PCI_SLOT_NAME::-1}*)
