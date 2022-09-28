#!/bin/bash


echo "# USBSTRAP[8]-node"
echo "Bootstrapping made easy."
mkdir -p output 2>&1 > /dev/null 
sleep 1

echo "## Parameters"
CENTOS_URL="http://repos.dfw.quadranet.com/centos/8-stream"

if [ -z "$KICKSTART_FILE" ]; then
	echo -n "(KICKSTART_FILE) Path to kickstart file: "
	read KICKSTART_FILE
	if [ -z "$KICKSTART_FILE" ]; then
		echo "Kickstart file required"
		exit 1
	fi
	if [ ! -f $KICKSTART_FILE ]; then
	    echo "Need a kickstart file"
		exit 1
	fi
fi

if [ -z "$OUTPUT_FILE" ]; then
	echo -n "(OUTPUT_FILE) Path to image file: "
	read OUTPUT_FILE
	if [ -z "$OUTPUT_FILE" ]; then
		OUTPUT_FILE=bootstrap.img
	fi
fi

if [ -z "$BOOTSTRAP_VMTYPE" ]; then
	BOOTSTRAP_VMTYPE=none
fi



if [ -z "$TGTSIZE" ]; then
	TGTSIZE=785
fi
TGTSIZE="${TGTSIZE}M"

echo "### Prereqs.."
APT=`which apt`
if [ -z "$APT" ]; then
	echo "CentOS detected (WARNING: untested)"
	sudo yum install -y syslinux pv qemu-img aria2
else
	echo "Ubuntu/Debian detected"
	sudo apt install -y syslinux pv qemu-utils  aria2 fdisk
fi

if [ -f $OUTPUT_FILE ]; then
    echo "existing bootstrap image detected!"
    sleep 2
    echo ""
    echo "warning, this script will destroy old images!"
    sleep 2
    echo "sleeping for operator cancellation incase this is not desired behavior"
    sleep 20
    echo "in the future, remove bootstrap.img before running to prevent this delay"
    rm $OUTPUT_FILE
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
if [ -z "$LOOPDEV" ]; then
  echo "Loopdev is empty"
  exit 1
fi

sudo losetup -P $LOOPDEV  $OUTPUT_FILE 1>&2
#LOOPDEV=$(losetup -a | grep bootstrap | awk -F':' '{print $1}')

if [ ! -b ${LOOPDEV}p1 ]; then
  echo "${LOOPDEV}p1 is not a device"
  exit 1
fi

if [ ! -f /usr/lib/SYSLINUX/mbr.bin ]; then
  echo "SYSLINUX bin missing!"
  exit 1
fi

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


sudo cp $KICKSTART_FILE BOOT/ks.cfg 1>&2
sudo cp $KICKSTART_FILE DATA/ks.cfg 1>&2
sudo cp assets/bootassets/* BOOT 1>&2


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
label nodelogic-controller
  menu label ^Kickstart Nodelogic (Controller Deploy)
  kernel vmlinuz
  append initrd=initrd.img nomodeset net.ifnames=0 biosdevname=0 inst.stage2=hd:LABEL=BOOT  inst.ks=hd:LABEL=DATA:/ks.cfg openstack-controller

label nodelogic
  menu label ^Kickstart Nodelogic (Node Deploy)
  kernel vmlinuz
  append initrd=initrd.img nomodeset net.ifnames=0 biosdevname=0 inst.stage2=hd:LABEL=BOOT  inst.ks=hd:LABEL=DATA:/ks.cfg 

label docker-portainer
  menu label ^Kickstart Nodelogic (Docker Deploy)
  kernel vmlinuz
  append initrd=initrd.img nomodeset net.ifnames=0 biosdevname=0 inst.stage2=hd:LABEL=BOOT  inst.ks=hd:LABEL=DATA:/ks.cfg docker-portainer

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
echo "** Use $OUTPUT_FILE to start NodeLogic **"
