#!/bin/bash

#global vars should be defined ASAP, otherwise they should be exported from the function they run in
#don't forget SSHKEYPUB, LANIPNET
PATH=/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
HOME=/root
LOGNAME=root
USER=root
NODEID=`hostid | tr '[:lower:]' '[:upper:]'`
GATEWAY="$(ip r | grep default | grep eth0 | awk '{print $3}')"
SUBNET_CIDR=$(ip r | grep eth0 | awk '{print $1}' | grep -v default)
START_ADDR=$(( $(echo $SUBNET_CIDR | rev | cut -d '.' -f 1 | rev | cut -d'/' -f 1) + 2 ))
END_ADDR=$(( $(echo $SUBNET_CIDR | rev | cut -d '.' -f 1 | rev | cut -d'/' -f 1) + 6 ))
IPADDR=$(ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | grep -v '::' | cut -d'/' -f1)
HOST=$(hostname)
	
MAINEVENT_GIT_URL="https://github.com/kzamore/mainevent"
MAINEVENT_INSTALL_PATH=/root/mainevent
TERRAFORM_VERSION="1.0.1"
TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
STARTERPACK_PATH=/root/starterpack/files
PACKSTACK_ZIP_URL=https://github.com/kzamore/starterpack/archive/refs/heads/master.zip
PACKSTACK_ANSWER_TEMPLATE_URL=https://raw.githubusercontent.com/kzamore/starterpack/master/openstack/files/dmzcloud.ans.template
PACKSTACK_ANSWER_TEMPLATE_PATH=${STARTERPACK_PATH}/dmzcloud.ans.template
NODELOGIC_CHECKIN_URL="https://api.nodelogic.net/v1/node/checkin?nodeID=$NODEID"
NODELOGIC_STARTERPACK_DOWNLOAD_URL="https://api.nodelogic.net/v1/starterpack/openstack/download?nodeID=$NODEID"

function update_system() {
	echo "#update system"
	dnf update -y
}

function configure_system() {
	sed -e 's/GRUB_CMDLINE_LINUX="/GRUB_CMDLINE_LINUX="net\.ifnames=0 nomodeset biosdevname=0/' -i /etc/default/grub
}

function apply_security_settings() {
	echo "#security settings"
	sed -i "s/dnssec-validation yes/dnssec-validation no/" /etc/named.conf
	setenforce 0
	echo SELINUX=permissive > /etc/selinux/config
}

function phone_home() {
	wget -O - $NODELOGIC_CHECKIN_URL
	echo "node_checkin::$?"
	TMP_PATH=$(mktemp)
	wget -O $TMP_PATH $NODELOGIC_STATERPACK_DOWNLOAD_URL
	echo "starterpack downloaded to $TMP_PATH"
}

function install_starterpack() {
	mkdir -p $STARTERPACK_PATH
	wget -O ${STARTERPACK_PATH}/starterpack.zip $PACKSTACK_ZIP_URL
	echo "starterpack_openstack_download::$?"

	curl $PACKSTACK_ANSWER_TEMPLATE_URL > $PACKSTACK_ANSWER_TEMPLATE_PATH

	configure_nameserver

	configure_hosts
	configure_sshd
}

function configure_nameserver() {
	echo "#its always dns"
	cat /etc/resolv.conf | grep -qe "^nameserver"
	if [ $? -ne 0 ]; then
        	echo "Adding nameserver" 
        	echo "nameserver 8.8.8.8" >> /etc/resolv.conf
	fi
}

function configure_hosts() {
	echo "#add localhost as hosts entry"
	cat /etc/hosts | grep -q "$HOST\$"
	echo "/ETC/HOSTS: $IPADDR $HOST"
	echo "$IPADDR $HOST" >> /etc/hosts
}

function configure_sshd() {
	echo "#add sshd ports"
	echo "Port 22" >> /etc/ssh/sshd_config
	echo "Port 220" >> /etc/ssh/sshd_config
	echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
	service sshd restart
}

function install_openstack() {
	dnf config-manager --enable powertools
	dnf install -y centos-release-openstack-wallaby
	dnf update -y
	dnf install -y openstack-packstack
	dnf install -y epel-release
	dnf install -y openvpn
	dnf remove -y epel-release
}

function install_sshkeys() {
	mkdir -p /root/.ssh/

	cat << EOF >> /root/.ssh/authorized_keys
$SSHKEYPUB
EOF
	chmod 700 /root/.ssh
	chmod 600 /root/.ssh/id_rsa /root/.ssh/authorized_keys
}

function configure_iptables() {
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
EOF
	if [ ! -z "$LANIPNET" ]; then
		cat << EOF >> /etc/sysconfig/iptables
-A NodeLogic-Public -s ${LANIPNET}.0/24 -i br-ex -p tcp -m state --state NEW -m tcp --dport 22 -j ACCEPT
EOF
	fi
	cat << EOF >> /etc/sysconfig/iptables
-A NodeLogic-Public -i br-ex -j DROP
COMMIT
EOF

	chmod 600 /etc/sysconfig/iptables
}

function configure_ssh_known_hosts() {
	echo "#local host is known host"
	cat /root/.ssh/known_hosts | grep -q "$HOST\$"
	if [ $? -ne 0 ]; then
	        mkdir -p /root/.ssh
	        echo "$HOST $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> /root/.ssh/known_hosts
	        echo "$(cat /etc/hosts | grep $HOST | awk '{print $1}') $(cat /etc/ssh/ssh_host_ecdsa_key.pub)" >> /root/.ssh/known_hosts
	        chmod 600 /root/.ssh/known_hosts
	        chmod 700 /root/.ssh
	fi
}

function packstack_build() {
	packstack --gen-answer-file=/root/${HOST}.ans
	sed -e "s/%CONTROLLERLIST%/$IPADDR/g" -e "s/%COMPUTELIST%/$IPADDR/g" -e "s/%NETWORKLIST%/$IPADDR/g" -e "s/%STORAGELIST%/$IPADDR/g" -e "s/%SAHARALIST%/$IPADDR/g" -e "s/%AMQPLIST%/$IPADDR/g" -e "s/%MYSQLLIST%/$IPADDR/g" -e "s/%REDISLIST%/$IPADDR/g" -e "s/%LDAPSERVER%/$IPADDR/g" -e "s/%HOSTNAME%/$HOST/g" < ${STARTERPACK_PATH}/dmzcloud.ans.template >> /root/${HOST}.anw
	IFS=$'\n'
	for line in $(cat /root/${HOST}.anw | egrep -ve '^(#|$)'); do
        	SNIP=$(echo $line | cut -d'=' -f1)
        	ANS=$(echo $line | cut -d'=' -f2- | sed -e 's/\//\\\//g')
        	echo "$SNIP -> $ANS"
        	sed -e "s/^${SNIP}=.*$/${SNIP}=${ANS}/" -i /root/${HOST}.ans 
	done
	cp /root/${HOST}.ans /root/${HOST}-original.ans

	generate_rsa_keys

	time packstack --answer-file=/root/${HOST}.ans 2>&1
	echo $?
	sleep 5
	cat /etc/resolv.conf | grep -qe "^nameserver"
	if [ $? -ne 0 ]; then
		echo "lost dns during install.. retrying"
		configure_nameserver
        	time packstack --answer-file=/root/${HOST}.ans 2>&1
	fi
	cat /proc/cpuinfo |egrep -e '(processor|model name)' | tail -2
}

function generate_rsa_keys() {
	if [ ! -f /root/.ssh/id_rsa ]; then
        	mkdir /root/.ssh
        	ssh-keygen -f /root/.ssh/id_rsa  -b 4096 -q -N ''
        	cat /root/.ssh/id_rsa.pub >> /root/.ssh/authorized_keys
        	chmod 700 /root/.ssh
        	chmod 600 /root/.ssh/authorized_keys /root/.ssh/id_rsa
	fi
}

function install_mainevent() {
	(cd /root && git clone $MAINEVENT_GIT_URL $MAINEVENT_INSTALL_PATH)
	TMPFILE=`mktemp --suffix .zip`
	wget -qO $TMPFILE $TERRAFORM_URL
	unzip -xod $MAINEVENT_INSTALL_PATH $TMPFILE
}

function mainevent_apply() {
	SUBNETADDR="$(( $RANDOM % 254))"
	if [ -f /root/keystonerc_admin ]; then
   		. /root/keystonerc_admin
	fi

	ssh-keygen -b 4096 -t rsa -f /root/cloudkey -q -N ''
	CLOUDKEY=$(cat /root/cloudkey.pub)
	OS_HOST=$(echo $OS_AUTH_URL | cut -d':' -f2 | cut -d'/' -f3)

	cat << EOR > ${MAINEVENT_INSTALL_PATH}/velocity-ops/deploy.tfvars
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

	cd ${MAINEVENT_INSTALL_PATH}/velocity-ops

	../terraform init
	../terraform apply -var-file="deploy.tfvars" -auto-approve
}


function branding() {
	echo "#branding"
	cat << EOI > /etc/issue
NodeLogic 8
Please wait as this instance comes online

EOI
}
