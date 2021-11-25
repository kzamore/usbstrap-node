#!/bin/bash

echo "# USBSTRAP[8]-node"
echo "Bootstrapping made easy."
mkdir -p output 2>&1 > /dev/null 
sleep 1

echo "## Parameters"
RERUNVARS="BOOTSTRAP_VMTYPE IPADDR NETMASK GATEWAY DNS  INITHOST  LANIPADDR LANNETMASK LANIPNET ADMINUSER  SSHKEY CENTOSURL CENTOSVER TIMEZONE"
#if you add or remove something 👇 then don't forget to do the same 👆
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
	#new algoriddem
	R=$(echo $IPADDR | rev | cut -d'.' -f 1 | rev)
	#R=$(printf "%.2d" $(($RANDOM % 99)))
	echo -n "(INITHOST) Enter Hostname of node: [dmzcloud$R] "
	read INITHOST
	if [ -z "$INITHOST" ]; then
		INITHOST=dmzcloud$R
	fi
fi
if [ -z "$LANIPADDR" ]; then
	echo -n "(LANIPADDR) Enter LAN IP Address: [Blank for single NIC] "
	read LANIPADDR
	if [ -z "$LANIPADDR" ]; then
		LANIPADDR=
	fi
fi
if [ -z "$LANNETMASK" -a ! -z "$LANIPADDR" ]; then
	echo -n "(LANNETMASK) Enter LAN Netmask: [255.255.255.0] "
	read LANNETMASK
	if [ -z "$LANNETMASK" ]; then
		LANNETMASK=255.255.255.0
	fi
fi
if [ -z "$LANIPNET" -a ! -z "$LANIPADDR"  ]; then
	DEF=$(echo $LANIPADDR | rev | cut -d'.' -f 2- | rev)
	echo -n "(LANIPNET) Enter LAN Network (must end with .0): [${DEF}.0] "
	read LANIPNET
	if [ -z "$LANIPNET" ]; then
		LANIPNET=$DEF
	else
		LANIPNET=$(echo $LANIPNET | rev | cut -d'.' -f 2- | rev)
	fi
fi
if [ -z "$ADMINUSER" ]; then
	DEF="vusr"
	echo -n "(ADMINUSER) Enter admin username [$DEF] "
	read ADMINUSER
	if [ -z "$ADMINUSER" ]; then
		ADMINUSER=$DEF
	else
		ADMINUSER=$(echo $ADMINUSER | cut -c-10)
	fi
fi
if [ -z "$ADMINPW" ]; then
	DEF=$(openssl rand -hex 8)
	echo -n "(ADMINPW) Enter admin password [$DEF] "
	read ADMINPW
	if [ -z "$ADMINPW" ]; then
		ADMINPW=$DEF
	fi

	ADMINPWSAFE=$(echo $ADMINPW | openssl passwd -6 -stdin)
fi
if [ -z "$SSHKEY" ]; then
	echo -n "(SSHKEY) Enter path to SSH Key [Default: create a new SSH Key] "
	read SSHKEY
	if [ ! -f "$SSHKEY" ]; then
		ssh-keygen -f output/node.key -b 4096
		SSHKEY=output/node.key
	fi
	SSHKEYPUB=$(ssh-keygen -yf $SSHKEY)
fi
if [ -z "$CENTOSURL" ]; then
	DEF="http://repos.dfw.quadranet.com/centos/8-stream"
	echo -n "(CENTOSURL) Enter URL to install CentOS 8 from: [$DEF] "
	read CENTOSURL
	if [ -z "$CENTOSURL" ]; then
		CENTOSURL=$DEF
	fi
fi
if [ -z "$CENTOSVER" ]; then
	DEF="latest"
	echo -n "(CENTOSVER) Enter version of CentOS 8 to install: [$DEF] "
	read CENTOSVER
	if [ -z "$CENTOSVER" ]; then
		CENTOSVER=$DEF
	fi
fi
if [ -z "$TIMEZONE" ]; then
	DEF="America/Chicago"
	echo -n "(TIMEZONE) Enter Timezone of system (e.g. UTC): [$DEF] "
	read TIMEZONE
	if [ -z "$TIMEZONE" ]; then
		TIMEZONE=$DEF
	fi
fi

if [ -z "$TGTSIZE" ]; then
	TGTSIZE=785
fi
TGTSIZE="${TGTSIZE}M"
	
if [ "$IPADDR" = "0.0.0.0" ]; then
	NETWORKLINE="dhcp "
	NETWORKLINE2="dhcp "
else
	NETWORKLINE="static ${BOOTPROTO} --gateway=$GATEWAY --ip=$IPADDR --nameserver=$DNS --netmask=$NETMASK "
	NETWORKLINE2="dhcp "
fi

#coming soon
#mkdir -p output 2> /dev/null
#for f in $RERUNVARS; do 
	reruntip="$f=\$${f} $reruntip"
#done
#reruntip="$reruntip \$0"
reruntip2="BOOTSTRAP_VMTYPE=$BOOTSTRAP_VMTYPE IPADDR=$IPADDR NETMASK=$NETMASK GATEWAY=$GATEWAY DNS=$DNS INITHOST=$INITHOST LANIPADDR=$LANIPADDR LANNETMASK=$LANNETMASK LANIPNET=$LANIPNET ADMINUSER=$ADMINUSER SSHKEY=$SSHKEY CENTOSURL=$CENTOSURL CENTOSVER=$CENTOSVER TIMEZONE=$TIMEZONE $0"
echo ""
echo "Rerun Tip:"
echo "\`\`\`=========================================================="
echo ""
echo $reruntip2
echo '#!/bin/bash' > output/bootstrap.sh
echo '#this script was automatically generated to quickly recreate the last image' >> output/bootstrap.sh
echo $reruntip2 >> output/bootstrap.sh
chmod +x output/bootstrap.sh
echo ""
echo "==========================================================\`\`\`"
echo ""

echo "### Prereqs.."
APT=`which apt`
if [ -z "$APT" ]; then
	echo "CentOS detected (WARNING: untested)"
	sudo yum install -y syslinux pv qemu-img aria2
else
	echo "Ubuntu/Debian detected"
	sudo apt install -y syslinux pv qemu-utils  aria2
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

CENTOSDVD="CentOS8DVD.iso"
if [ ! -f "$CENTOSDVD" ]; then 
aria2c -s 16 -x 16 --auto-file-renaming=false -o $CENTOSDVD  ${CENTOSURL}/isos/x86_64/CentOS-Stream-8-x86_64-latest-boot.iso
else
echo "cached $(ls -l ${CENTOSDVD})"
fi


echo  "### Image creation.."
dd if=/dev/zero of=bootstrap.img bs=1 count=0 seek=${TGTSIZE}
echo "n



+780M
t
c
a
n




w" | fdisk bootstrap.img 1>&2
#this seems dangerous. it may have accidentally blown away one of my boot disks. this software does not come with any warranty
LOOPDEV=$(losetup -f)
sudo losetup -P $LOOPDEV  bootstrap.img 1>&2
#LOOPDEV=$(losetup -a | grep bootstrap | awk -F':' '{print $1}')

sudo mkfs -t vfat -n "BOOT" ${LOOPDEV}p1 1>&2
sudo mkfs -L "DATA" ${LOOPDEV}p2 1>&2

echo "### Installing syslinux"
sudo dd conv=notrunc bs=440 count=1 if=/usr/lib/SYSLINUX/mbr.bin of=${LOOPDEV} 1>&2
sudo syslinux -i ${LOOPDEV}p1 1>&2

mkdir BOOT DATA DVD 1>&2
sudo mount ${LOOPDEV}p1 BOOT 1>&2
sudo mount ${LOOPDEV}p2 DATA 1>&2
sudo mount ${CENTOSDVD} DVD 1>&2

echo "### Adding isolinux and syslinux modules"
sudo cp -av DVD/isolinux/* BOOT 1>&2
sudo cp -av /usr/lib/syslinux/modules/bios/menu.c32 BOOT 1>&2
sudo mv BOOT/isolinux.cfg BOOT/syslinux.cfg 1>&2
sudo mkdir BOOT/images 1>&2
sudo cp -av DVD/images/install.img BOOT/images 1>&2
sudo cp -av default/* BOOT 1>&2
BOOTSTRAP_DEPLOYTYPE=".${BOOTSTRAP_DEPLOYTYPE}"


. kickstart.sh

NETWORKETH1=
if [ ! -z "$LANIPADDR" ]; then
	NETWORKETH1="network  --bootproto=static --device=eth1                      --ip=${LANIPADDR}                      --netmask=${LANNETMASK} --activate"
fi

echo "### Creating kickstart config"
ksHeader output/bootstrap.ks
ksPost output/bootstrap.ks
sudo cp output/bootstrap.ks BOOT/ks.cfg 1>&2
sudo cp output/bootstrap.ks DATA/ks.cfg 1>&2
sudo cp assets/bootassets/* BOOT 1>&2

#BOOTSTRAP_FILE="BOOT/ks.cfg${BOOTSTRAP_DEPLOYTYPE}.template"
#if [ -f "${BOOTSTRAP_FILE}" ]; then
# sudo cat ${BOOTSTRAP_FILE} | sed -e "s/%NETWORKLINE%/${NETWORKLINE}/" -e "s/%NETWORKLINE2%/${NETWORKLINE2}/" -e "s/%HOSTNAME%/${INITHOST}/" -e "s/%LANIPADDR%/${LANIPADDR}/" -e "s/%LANNETMASK%/${LANNETMASK}/" -e "s/%LANIPNET%/${LANIPNET}/g" -e "s/%ADMINUSER%/${ADMINUSER}/g" -e "%s/%ADMINPW%/${ADMINPWSAFE}/g" -e "%s/%SSHPUBKEY%/${SSHKEYPUBSAFE}/g" | sudo tee  BOOT/ks.cfg
# cp BOOT/ks.cfg output/bootstrap.ks
#fi

echo "### Writing syslinux config"
cat << EOF | sudo tee  BOOT/syslinux.cfg 1>&2
default vesamenu.c32
#prompt 1
timeout 10

display boot.msg

# Clear the screen when exiting the menu, instead of leaving the menu displayed.
# For vesamenu, this means the graphical background is still displayed without
# the menu itself for as long as the screen remains in graphics mode.
menu clear
menu background splash.png
menu title NodeLogic 8
menu vshift 8
menu rows 18
menu margin 8
#menu hidden
menu helpmsgrow 15
menu tabmsgrow 13

# Border Area
menu color border * #00000000 #00000000 none

# Selected item
menu color sel 0 #ffffffff #00000000 none

# Title bar
menu color title 0 #ff7ba3d0 #00000000 none

# Press [Tab] message
menu color tabmsg 0 #ff3a6496 #00000000 none

# Unselected menu item
menu color unsel 0 #84b8ffff #00000000 none

# Selected hotkey
menu color hotsel 0 #84b8ffff #00000000 none

# Unselected hotkey
menu color hotkey 0 #ffffffff #00000000 none

# Help text
menu color help 0 #ffffffff #00000000 none

# A scrollbar of some type? Not sure.
menu color scrollbar 0 #ffffffff #ff355594 none

# Timeout msg
menu color timeout 0 #ffffffff #00000000 none
menu color timeout_msg 0 #ffffffff #00000000 none

# Command prompt text
menu color cmdmark 0 #84b8ffff #00000000 none
menu color cmdline 0 #ffffffff #00000000 none

# Do not display the actual menu unless the user presses a key. All that is displayed is a timeout message.

# menu tabmsg Press Tab to edit boot configuration options

menu separator # insert an empty line
menu separator # insert an empty line

label nodelogic
  menu label ^Kickstart Nodelogic (Node Deploy)
  kernel vmlinuz
  append initrd=initrd.img nomodeset net.ifnames=0 biosdevname=0 inst.stage2=hd:LABEL=BOOT  inst.ks=hd:LABEL=DATA:/ks.cfg 

label linux
  menu label ^Install CentOS 8 (NetInstall Only)
  kernel vmlinuz
  append initrd=initrd.img nomodeset inst.stage2=hd:LABEL=BOOT quiet

menu separator # insert an empty line

# utilities submenu
menu begin ^Troubleshooting
  menu title Troubleshooting

label rescue
  menu indent count 5
  menu label ^Rescue system
  text help
        If the system will not boot, this lets you access files
        and edit config files to try to get it booting again.
  endtext
  kernel vmlinuz
  append initrd=initrd.img inst.stage2=hd:LABEL=BOOT rescue quiet

label memtest
  menu label Run a ^memory test
  text help
        If your system is having issues, a problem with your
        system's memory may be the cause. Use this utility to
        see if the memory is working correctly.
  endtext
  kernel memtest

menu separator # insert an empty line

label local
  menu label Boot from ^local drive
  localboot 0xffff

menu separator # insert an empty line
menu separator # insert an empty line

label returntomain
  menu label Return to ^main menu
  menu exit

menu end




EOF

echo "### Cleaning up"
for d in BOOT DATA; do 
sudo du -h --max-depth=1 $d 1>&2
sudo umount $d && sudo rm -rf $d 1>&2
done
sudo umount DVD && sudo rm -rf DVD 1>&2

sudo losetup -d ${LOOPDEV} 1>&2

if [ "$BOOTSTRAP_VMTYPE" != "none" ]; then
	echo "Creating VM image..."
	qemu-img convert -p -f raw -O $BOOTSTRAP_VMTYPE bootstrap.img bootstrap.$BOOTSTRAP_VMTYPE
fi
echo "** Use bootstrap.img to start NodeLogic **"
