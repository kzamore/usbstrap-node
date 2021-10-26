#!/bin/bash

function ksHeader() {
	cat << EOF > $1
auth  --enableshadow  --passalgo=sha512
url --url="${CENTOSURL}/BaseOS/x86_64/os/"
text
firewall --disabled
firstboot --disable
ignoredisk --only-use=sda
keyboard --vckeymap=us --xlayouts=''
lang en_US.UTF-8
network  --device=eth0 --hostname=$INITHOST --activate --bootproto=$NETWORKLINE
$NETWORKETH1
#reboot
rootpw --iscrypted $ADMINPWSAFE
services --enabled="chronyd"
skipx
timezone $TIMEZONE
timezone America/Chicago
user --name=$ADMINUSER --password=$ADMINPWSAFE --iscrypted
bootloader --append="net.ifnames=0 biosdevname=0 crashkernel=auto" --location=mbr --boot-drive=sda
zerombr
clearpart --all --initlabel
part biosboot --fstype=biosboot --size=1 --ondisk=sda
part /boot --fstype="ext4" --size=5000 --ondisk=sda
part pv.01 --size=112500 --ondisk=sda
part pv.02 --ondisk=sda --size=50 --grow
volgroup vg-01 pv.01
volgroup cinder-volumes pv.02
logvol /  --fstype="ext4" --size=102400 --name=root --vgname=vg-01
logvol swap  --size=8192 --name=swap --vgname=vg-01

EOF
}

function ksPost() {
	cat << 'EOP' >> $1
%post --log=/root/nodelogic.log
exec < /dev/tty3 > /dev/tty3
chvt 3

mkdir -p /root/nodelogic
curl https://raw.githubusercontent.com/kzamore/usbstrap-node/motocenter/assets/install/kickstart.sh > /root/nodelogic/kickstart.sh

if [ -f /root/nodelogic/kickstart.sh ]; then
	. /root/nodelogic/kickstart.sh
else
	echo "Could not fetch LiveInstall functions"
	sleep 3600
fi
EOP

	echo "SSHKEYPUB=$SSHKEYPUB" >> $1
	echo "LANIPNET=$LANIPNET" >> $1
	cat << 'EOP' >> $1

update_system
configure_system
apply_security_settings
phone_home
install_openstack

install_sshkeys
configure_iptables

install_starterpack
configure_ssh_known_hosts

packstack_build

install_mainevent
mainevent_apply

branding


echo "#pausing for debug"
sleep 600

chvt 1

%end

%packages
@^minimal-environment
biosdevname
caching-nameserver
chrony
curl
git
iptables-services
kexec-tools
lsof
openssh-server
unzip
wget
-iwl6000g2a-firmware
-iwl3160-firmware
-iwl105-firmware
-iwl6050-firmware
-iwl6000-firmware
-iwl5000-firmware
-iwl2030-firmware
-iwl135-firmware
-iwl1000-firmware
-iwl7260-firmware
-iwl5150-firmware
-iwl2000-firmware
-iwl100-firmware


%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end
%anaconda
pwpolicy root --minlen=6 --minquality=1 --notstrict --nochanges --notempty
pwpolicy user --minlen=6 --minquality=1 --notstrict --nochanges --emptyok
pwpolicy luks --minlen=6 --minquality=1 --notstrict --nochanges --notempty
%end

EOP
}

