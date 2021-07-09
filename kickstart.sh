#!/bin/bash

function ksHeader() {
	cat << EOF > $1
auth  --enableshadow  --passalgo=sha512
install
url --url="${CENTOSURL}"
text
firewall --disabled
firstboot --disable
ignoredisk --only-use=sda
keyboard --vckeymap=us --xlayouts=''
lang en_US.UTF-8
network  --device=eth0 --hostname=$INITHOST --activate --bootproto=$NETWORKLINE
$NETWORKETH1
reboot
rootpw --iscrypted $ADMINPWSAFE
services --enabled="chronyd"
skipx
timezone $TIMEZONE
timezone America/Chicago
user --name=$ADMINUSER --password=$ADMINPWSAFE --iscrypted
bootloader --append="net.ifnames=0 biosdevname=0 crashkernel=auto" --location=mbr --boot-drive=sda
zerombr
clearpart --all --initlabel
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
%post

yum update -y
sed -i "s/dnssec-validation yes/dnssec-validation no/" /etc/named.conf
echo SELINUX=permissive > /etc/selinux/config
if [ -e /etc/ssh/sshd_config ]; then
  sed -e "/PermitRootLogin/d" -e "/Port 22/a Port 220" -i /etc/ssh/sshd_config
  echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
fi
NODEID=`hostid | tr '[:lower:]' '[:upper:]'`
wget -O - https://api.nodelogic.net/v1/node/checkin?nodeID=$NODEID
echo "node_checkin::$?"
yum install -y unzip
wget -O $(mktemp) https://api.nodelogic.net/v1/starterpack/openstack/download?nodeID=$NODEID
wget -O /tmp/starterpack.zip https://github.com/kzamore/starterpack/archive/refs/heads/master.zip
echo "starterpack_openstack_download::$?"
(cd /root && unzip /tmp/starterpack.zip)

yum install -y epel-release
yum install -y openvpn lsof iptables-services ntp ntpdate 

mkdir -p /root/.ssh/

cat << EOF > /root/.ssh/authorized_keys
EOP

echo "$SSHKEYPUB" >> $1
	cat << 'EOP' >> $1
EOF
chmod 700 /root/.ssh
chmod 600 /root/.ssh/id_rsa /root/.ssh/authorized_keys
INTF=eth0
cat << EOF > /etc/sysconfig/iptables
*filter
:INPUT ACCEPT [0:0]
:FORWARD ACCEPT [0:0]
:OUTPUT ACCEPT [0:0]
:NodeLogic-Public - [0:0]
-A INPUT -j NodeLogic-Public
-A INPUT -i lo -j ACCEPT
-A FORWARD -j NodeLogic-Public
-A NodeLogic-Public -i br-ex -m state --state RELATED,ESTABLISHED -j ACCEPT
-A NodeLogic-Public -i br-ex -p tcp -m state --state NEW -m tcp --dport 220 -j ACCEPT
-A NodeLogic-Public -i br-ex -p tcp -m state --state NEW -m tcp --dport 443 -j ACCEPT
-A NodeLogic-Public -i br-ex -p icmp -j ACCEPT
-A NodeLogic-Public -s 66.45.242.170/32 -i br-ex -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
-A NodeLogic-Public -s 66.45.242.170/32 -i br-ex -p tcp -m state --state NEW -m tcp --dport 10050 -j ACCEPT
EOP

if [ ! -z "$LANIPNET" ]; then
	cat << EOP >> $1
-A NodeLogic-Public -s ${LANIPNET}.0/24 -i br-ex -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
EOP
fi

	cat << 'EOP' >> $1
-A NodeLogic-Public -i br-ex -j DROP
COMMIT
EOF

chmod 600 /etc/sysconfig/iptables

cat << EOG > /root/bootstrap.sh
#!/bin/bash

TGTDISKDEV=/dev/sdb
TGTPARTDEV="1"

sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk 
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk
    # default - extend partition to end of disk
  p # print the in-memory partition table
  t # set type
    # default - first disk
  31 # linux LVM
  w # write the partition table
  q # and we're done
EOF
pvcreate /dev/sdb1
vgcreate cinder-volumes /dev/sdb1
cd /root/starterpack/openstack
./01_update.sh
./02_openstack.sh
NODEID=`hostid | tr '[:lower:]' '[:upper:]'`
wget -O - https://api.nodelogic.net/v1/starterpack/openstack/checkin?nodeID=$NODEID
echo "starterpack_openstack_checkin::$?"

EOG

chmod 755 /root/bootstrap.sh
cat << EOL > /root/rc.local
#!/bin/bash
if [ ! -f /root/.nodelogic_boot ]; then 
	/root/bootstrap.sh
	touch /root/.nodelogic_boot
	reboot
fi
EOL
cat /etc/rc.local >> /root/rc.local
mv /root/rc.local /etc/rc.local
chmod 755 /etc/rc.local

sed -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="net\.ifnames=0 biosdevname=0/' -i /etc/default/grub


%end

%packages
biosdevname
caching-nameserver
chrony
kexec-tools
openssh-server
wget
lsof
iptables-services
ntp
ntpdate

%end

%addon com_redhat_kdump --enable --reserve-mb='auto'

%end
EOP
}

