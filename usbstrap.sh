#!/bin/bash

echo "To avoid delays, consider running 'sudo ls' before running this script"
sleep 1

if [ -z "$BOOTSTRAP_DEPLOYTYPE" ]; then
	BOOTSTRAP_DEPLOYTYPE="node"
fi

if [ -z "$BOOTSTRAP_VMTYPE" ]; then
	BOOTSTRAP_VMTYPE=none
fi
if [ -z "$IPADDR" ]; then
	echo -n "(IPADDR) Enter IP Address: [0.0.0.0 (dhcp)] "
	read IPADDR
	if [ -z "$IPADDR" ]; then
		IPADDR=0.0.0.0
	fi
fi
if [ -z "$NETMASK" -a "$IPADDR" != "0.0.0.0" ]; then
	echo -n "(NETMASK) Enter Netmask: "
	read NETMASK
fi
if [ -z "$GATEWAY" -a "$IPADDR" != "0.0.0.0" ]; then
	echo -n "(GATEWAY) Enter Gateway IP Address: "
	read GATEWAY
fi
if [ -z "$DNS" -a "$IPADDR" != "0.0.0.0" ]; then
	echo -n "(DNS) Enter DNS IP Address: [8.8.8.8] "
	read DNS
	if [ -z "$DNS" ]; then
		DNS=8.8.8.8
	fi
fi
if [ -z "$INITHOST" ]; then
	R=$(printf "%.2d" $(($RANDOM % 99)))
	echo -n "(INITHOST) Enter Hostname of node: [dmzcloud$R] "
	read INITHOST
	if [ -z "$INITHOST" ]; then
		INITHOST=dmzcloud$R
	fi
fi
if [ -z "$LANIPADDR" ]; then
	echo -n "(LANIPADDR) Enter LAN IP Address: [172.17.0.1] "
	read LANIPADDR
	if [ -z "$LANIPADDR" ]; then
		LANIPADDR=172.17.0.1
	fi
fi
if [ -z "$LANNETMASK" ]; then
	echo -n "(LANNETMASK) Enter LAN Netmask: [255.255.255.0] "
	read LANNETMASK
	if [ -z "$LANNETMASK" ]; then
		LANNETMASK=255.255.255.0
	fi
fi
if [ -z "$LANIPNET" ]; then
	DEF=$(echo $LANIPADDR | rev | cut -d'.' -f 2- | rev)
	echo -n "(LANIPNET) Enter LAN Network (must end with .0): [${DEF}.0] "
	read LANIPNET
	if [ -z "$LANIPNET" ]; then
		LANIPNET=$DEF
	else
		LANIPNET=$(echo $LANIPNET | rev | cut -d'.' -f 2- | rev)
	fi
fi

if [ -z "$TGTSIZE" ]; then
	TGTSIZE=75
fi
TGTSIZE="${TGTSIZE}M"
	
if [ "$IPADDR" = "0.0.0.0" ]; then
	NETWORKLINE="dhcp "
	NETWORKLINE2="dhcp "
else
	NETWORKLINE="static ${BOOTPROTO} --gateway=$GATEWAY --ip=$IPADDR --nameserver=$DNS --netmask=$NETMASK "
	NETWORKLINE2="dhcp "
fi
echo ""
echo "Rerun Tip:"
echo "=========================================================="
echo ""
echo "BOOTSTRAP_VMTYPE=$BOOTSTRAP_VMTYPE IPADDR=$IPADDR NETMASK=$NETMASK GATEWAY=$GATEWAY DNS=$DNS INITHOST=$INITHOST LANIPADDR=$LANIPADDR LANNETMASK=$LANNETMASK LANIPNET=$LANIPNET $0"
echo '#!/bin/bash' > bootstrap.sh
echo "BOOTSTRAP_VMTYPE=$BOOTSTRAP_VMTYPE IPADDR=$IPADDR NETMASK=$NETMASK GATEWAY=$GATEWAY DNS=$DNS INITHOST=$INITHOST LANIPADDR=$LANIPADDR LANNETMASK=$LANNETMASK LANIPNET=$LANIPNET $0" >> bootstrap.sh
chmod +x bootstrap.sh
echo ""
echo "=========================================================="
echo ""

echo "Prereqs.."
APT=`which apt`
if [ -z "$APT" ]; then
sudo yum install -y syslinux pv qemu-img aria2
else
sudo apt install -y syslinux pv qemu-utils aria2
fi

if [ -f bootstrap.img ]; then
    echo "existing bootstrap image detected!"
    sleep 2
    echo ""
    echo "warning, this script will destroy old images!"
    sleep 2
    echo "sleeping for operator cancellation incase this is not desired behavior"
    sleep 20
    echo "in the future, remove bootstrap.img before running to prevent this delay"
    rm bootstrap.img
fi


if [ ! -f CentOSDVD.iso ]; then 
aria2c -s 16 -x 16 --auto-file-renaming=false -o CentOSDVD.iso  http://repo1.dal.innoscale.net/centos/7.9.2009/isos/x86_64/CentOS-7-x86_64-DVD-2009.iso
#aria2c -x16 --auto-file-renaming=false -o CentOSDVD.iso http://mirror.centos.org/centos/7/isos/x86_64/CentOS-7-x86_64-DVD-2003.iso
#aria2c -x5 -o CentOSDVD.iso http://mirrors.raystedman.org/centos/7/isos/x86_64/CentOS-7-x86_64-DVD-2003.iso
else
echo "cached $(ls -l CentOSDVD.iso)"
fi


echo  "Image creation.."
dd if=/dev/zero of=bootstrap.img bs=1 count=0 seek=${TGTSIZE}
echo "n



+250M
t
c
a
n




w" | fdisk bootstrap.img
LOOPDEV=$(losetup -f)
sudo losetup -P $LOOPDEV  bootstrap.img 
#LOOPDEV=$(losetup -a | grep bootstrap | awk -F':' '{print $1}')

sudo mkfs -t vfat -n "BOOT" ${LOOPDEV}p1
sudo mkfs -L "DATA" ${LOOPDEV}p2

echo "Installing syslinux"
sudo dd conv=notrunc bs=440 count=1 if=/usr/lib/SYSLINUX/mbr.bin of=${LOOPDEV}
sudo syslinux -i ${LOOPDEV}p1

mkdir BOOT DATA DVD
sudo mount ${LOOPDEV}p1 BOOT
sudo mount ${LOOPDEV}p2 DATA
sudo mount CentOSDVD.iso DVD

echo "Bootstrap deploying..."
sudo cp -av DVD/isolinux/* BOOT
sudo mv BOOT/isolinux.cfg BOOT/syslinux.cfg
sudo cp -av default/* BOOT
BOOTSTRAP_DEPLOYTYPE=".${BOOTSTRAP_DEPLOYTYPE}"
BOOTSTRAP_FILE="BOOT/ks.cfg${BOOTSTRAP_DEPLOYTYPE}.template"
if [ -f "${BOOTSTRAP_FILE}" ]; then
 sudo cat ${BOOTSTRAP_FILE} | sed -e "s/%NETWORKLINE%/${NETWORKLINE}/" -e "s/%NETWORKLINE2%/${NETWORKLINE2}/" -e "s/%HOSTNAME%/${INITHOST}/" -e "s/%LANIPADDR%/${LANIPADDR}/" -e "s/%LANNETMASK%/${LANNETMASK}/" -e "s/%LANIPNET%/${LANIPNET}/g" | sudo tee  BOOT/ks.cfg
 cp BOOT/ks.cfg bootstrap.ks
fi

cat << EOF | sudo tee -a  BOOT/syslinux.cfg
label linux
  menu label ^Kickstart Nodelogic (Node Deploy)
  kernel vmlinuz
  append initrd=initrd.img net.ifnames=0 biosdevname=0 inst.stage2=hd:sdb2:/ ks=hs:sdb1:/ks.cfg 
EOF

echo "Cleaning up.."
for d in BOOT DATA; do 
sudo du -h --max-depth=1 $d
sudo umount $d && sudo rm -rf $d
done
sudo umount DVD && sudo rm -rf DVD

sudo losetup -d ${LOOPDEV}

if [ "$BOOTSTRAP_VMTYPE" != "none" ]; then
	echo "Creating VM image..."
	qemu-img convert -p -f raw -O $BOOTSTRAP_VMTYPE bootstrap.img bootstrap.$BOOTSTRAP_VMTYPE
fi
echo "Use bootstrap.img to start NodeLogic"
