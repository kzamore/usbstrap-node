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
echo "#update system"
dnf update -y

echo "#security settings"
sed -i "s/dnssec-validation yes/dnssec-validation no/" /etc/named.conf
setenforce 0
echo SELINUX=permissive > /etc/selinux/config

NODEID=`hostid | tr '[:lower:]' '[:upper:]'`
wget -O - https://api.nodelogic.net/v1/node/checkin?nodeID=$NODEID
echo "node_checkin::$?"
wget -O $(mktemp) https://api.nodelogic.net/v1/starterpack/openstack/download?nodeID=$NODEID
wget -O /tmp/starterpack.zip https://github.com/kzamore/starterpack/archive/refs/heads/master.zip
echo "starterpack_openstack_download::$?"

dnf config-manager --enable powertools
dnf install -y centos-release-openstack-wallaby
dnf update -y
dnf install -y openstack-packstack
dnf install -y epel-release
dnf install -y openvpn
dnf remove -y epel-release

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

NODEID=`hostid | tr '[:lower:]' '[:upper:]'`
#wget -O - https://api.nodelogic.net/v1/starterpack/openstack/checkin?nodeID=$NODEID
#echo "starterpack_openstack_checkin::$?"

mkdir -p /root/starterpack/files
curl https://raw.githubusercontent.com/kzamore/starterpack/master/openstack/files/dmzcloud.ans.template > /root/starterpack/files/dmzcloud.ans.template

echo "#its always dns"

cat /etc/resolv.conf | grep -qe "^nameserver"
if [ $? -ne 0 ]; then
        echo "Adding nameserver" 
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
fi

echo "#add localhost as hosts entry"
cat /etc/hosts | grep -q "$(hostname)\$"
IPADDR=$(ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | grep -v '::' | cut -d'/' -f1)
echo "/ETC/HOSTS: $IPADDR $(hostname)"
echo "$IPADDR $(hostname)" >> /etc/hosts

echo "#add sshd ports"
echo "Port 22" >> /etc/ssh/sshd_config
echo "Port 220" >> /etc/ssh/sshd_config
echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
/usr/sbin/sshd -D &

echo "#local host is known host"
cat ~/.ssh/known_hosts | grep -q "$(hostname)\$"
if [ $? -ne 0 ]; then
        mkdir -p ~/.ssh
        echo "$(hostname) $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> ~/.ssh/known_hosts
        echo "$(cat /etc/hosts | grep $(hostname) | awk '{print $1}') $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> ~/.ssh/known_hosts
        chmod 600 ~/.ssh/known_hosts
        chmod 700 ~/.ssh
fi

HOST=$(hostname)
packstack --gen-answer-file=/root/${HOST}.ans
sed -e "s/%CONTROLLERLIST%/$IPADDR/g" -e "s/%COMPUTELIST%/$IPADDR/g" -e "s/%NETWORKLIST%/$IPADDR/g" -e "s/%STORAGELIST%/$IPADDR/g" -e "s/%SAHARALIST%/$IPADDR/g" -e "s/%AMQPLIST%/$IPADDR/g" -e "s/%MYSQLLIST%/$IPADDR/g" -e "s/%REDISLIST%/$IPADDR/g" -e "s/%LDAPSERVER%/$IPADDR/g" -e "s/%HOSTNAME%/$HOST/g" < /root/starterpack/files/dmzcloud.ans.template >> /root/${HOST}.anw
IFS=$'\n'
for line in $(cat /root/${HOST}.anw | egrep -ve '^(#|$)'); do
        SNIP=$(echo $line | cut -d'=' -f1)
        ANS=$(echo $line | cut -d'=' -f2- | sed -e 's/\//\\\//g')
        echo "$SNIP -> $ANS"
        sed -e "s/^${SNIP}=.*$/${SNIP}=${ANS}/" -i /root/${HOST}.ans 
done
cp /root/${HOST}.ans /root/${HOST}-original.ans

if [ ! -f /root/.ssh/id_rsa ]; then
        mkdir /root/.ssh
        ssh-keygen -f /root/.ssh/id_rsa  -b 4096 -q -N ''
        cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
        chmod 700 /root/.ssh
        chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa
fi

time packstack --answer-file=/root/${HOST}.ans 2>&1
echo $?
sleep 5
cat /etc/resolv.conf | grep -qe "^nameserver"
if [ $? -ne 0 ]; then
        echo "Adding nameserver"
        echo "nameserver 8.8.8.8" >> /etc/resolv.conf
        time packstack --answer-file=/root/${HOST}.ans 2>&1
fi
cat /proc/cpuinfo |egrep -e '(processor|model name)' | tail -2

(cd /root && git clone https://github.com/kzamore/mainevent /root/mainevent)
TMPFILE=`mktemp --suffix .zip`
wget -qO $TMPFILE https://releases.hashicorp.com/terraform/1.0.1/terraform_1.0.1_linux_amd64.zip
unzip -xod /root/mainevent $TMPFILE
SUBNETADDR="$(( $RANDOM % 254))"
if [ -f /root/keystonerc_admin ]; then
   . /root/keystonerc_admin
fi
OS_HOST=$(echo $OS_AUTH_URL | cut -d':' -f2 | cut -d'/' -f3)
SUBNET_CIDR=$(ip r | grep eth0 | awk '{print $1}' | grep -v default)
START_ADDR=$(( $(echo $SUBNET_CIDR | rev | cut -d '.' -f 1 | rev | cut -d'/' -f 1) + 2 ))
END_ADDR=$(( $(echo $SUBNET_CIDR | rev | cut -d '.' -f 1 | rev | cut -d'/' -f 1) + 6 ))

ssh-keygen -b 4096 -t rsa -f /root/cloudkey -q -N ''
CLOUDKEY=$(cat /root/cloudkey.pub)

cat << EOR > /root/mainevent/velocity-ops/deploy.tfvars
openstack_host = "$HOST"
openstack_password = "$OS_PASSWORD"
cloudkey_value = "$CLOUDKEY"
public_subnet_cidr= "$SUBNET_CIDR"
public_subnet_gateway= "${GATEWAY}"
public_subnet_start_ip= "$START_ADDR"
public_subnet_end_ip= "$END_ADDR"
shared_subnet_cidr= "10.${SUBNETADDR}.68.0/24"
shared_subnet_gateway= "10.${SUBNETADDR}.68.1"
shared_subnet_start_ip= "10.${SUBNETADDR}.68.2"
shared_subnet_end_ip= "10.${SUBNETADDR}.68.254"
EOR

cd /root/mainevent/velocity-ops

../terraform init
../terraform apply -var-file="deploy.tfvars" -auto-approve

sed -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="net\.ifnames=0 nomodeset biosdevname=0/' -i /etc/default/grub

#branding
cat << EOI > /etc/issue
NodeLogic 8
Authorize this instance at https://nodelogic.net/a/$NODEID

EOI

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

