#!/bin/bash

#global vars should be defined ASAP, otherwise they should be exported from the function they run in
export PATH=/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
export HOME=/root
export LOGNAME=root
export USER=root
export NODEID=`hostid | tr '[:lower:]' '[:upper:]'`
export GATEWAY="$(ip r | grep default | grep eth0 | awk '{print $3}')"
export SUBNET_CIDR=$(ip r | grep eth0 | awk '{print $1}' | grep -v default)
export SUBNET="$(echo $SUBNET_CIDR | cut -d '.' -f -3)."
export START_ADDR="${SUBNET}$(( $(echo $SUBNET_CIDR | rev | cut -d '.' -f 1 | rev | cut -d'/' -f 1) + 2 ))"
export END_ADDR="${SUBNET}$(( $(echo $SUBNET_CIDR | rev | cut -d '.' -f 1 | rev | cut -d'/' -f 1) + 6 ))"
export IPADDR=$(ip a show dev eth0 | grep 'inet ' | awk '{print $2}' | grep -v '::' | cut -d'/' -f1)
export HOST=$(hostname)
	
export MAINEVENT_GIT_URL="https://github.com/kzamore/mainevent"
export MAINEVENT_INSTALL_PATH=/root/mainevent
export TERRAFORM_VERSION="1.0.1"
export TERRAFORM_URL="https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"
export STARTERPACK_PATH=/root/starterpack/files
export PACKSTACK_ZIP_URL=https://github.com/kzamore/starterpack/archive/refs/heads/master.zip
export PACKSTACK_ANSWER_TEMPLATE_URL=https://raw.githubusercontent.com/kzamore/starterpack/master/openstack/files/dmzcloud.ans.template
export PACKSTACK_ANSWER_TEMPLATE_PATH=${STARTERPACK_PATH}/dmzcloud.ans.template
export NODELOGIC_CHECKIN_URL="https://api.nodelogic.net/v1/node/checkin?nodeID=$NODEID"
export NODELOGIC_STARTERPACK_DOWNLOAD_URL="https://api.nodelogic.net/v1/starterpack/openstack/download?nodeID=$NODEID"

. /root/.global.vars

#we should
# update_system
# update_getty "configuring system"
# configure_nameserver
# configure_hosts
# configure_sshd
# configure_ssh_known_hosts
# packstack_build
# mainevent_apply
# branding
# configure_final

function configure_final() {
	systemctl disable NetworkManager
	systemctl enable network
}

function update_system() {
	update_getty "updating system"
	dnf update -y
}

function configure_nameserver() {
	cat /etc/resolv.conf | grep -qe "^nameserver"
	if [ $? -ne 0 ]; then
        	echo "Adding nameserver" 
        	echo "nameserver 8.8.8.8" >> /etc/resolv.conf
	fi
}

function configure_hosts() {
	cat /etc/hosts | grep -q "$HOST\$"
	if [ $? -ne 0 ]; then
		echo "/ETC/HOSTS: $IPADDR $HOST"
		echo "$IPADDR $HOST" >> /etc/hosts
	fi
}

function configure_sshd() {
	echo "#add sshd ports"
	echo "Port 22" >> /etc/ssh/sshd_config
	echo "Port 220" >> /etc/ssh/sshd_config
	echo "PermitRootLogin without-password" >> /etc/ssh/sshd_config
	service sshd restart
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
	update_getty "building the nodelogic cloud"
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

function mainevent_apply() {
	update_getty "terraforming the nodelogic cloud"
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
	result=$?
	if [ $result -ne 0 ]; then
		echo "terraform apply still has missing steps ($result)"
		../terraform apply -var-file="deploy.tfvars" -auto-approve
		result=$?
		if [ $result -ne 0 ]; then echo "terraform apply failed twice ($result)"; fi
	fi
}

function update_getty() {
	USRMSG="$*"
	cat << EOI > /etc/issue
NodeLogic 8
Current Task: $USRMSG

EOI
	systemctl restart getty@tty1
}

function branding() {
	echo "#branding"
	if [ -f /root/.nodelogic-openstack-controller ]; then
		text="controller"
	else
		text="instance"
	fi
	cat << EOI > /etc/issue
    oooo==+===oooo=+==ooooooooooooooooooooo=+=+=====oooooo===+==+=+==+==ooo
    oo=o:  .+o===o:  ~ooooooooo==ooooooo=o+         .~+ooo=.           =ooo
    oooo:    :===o:  ~o=oooooooo=ooooooooo+  .+++:~~   ~oo=   :++++++++oooo
    oo=o+     ~=oo:  ~o=oooooo=++=oooooo=o+  .=o==o=+.  :o=.  oo======ooooo
    oo=o:  ~:  .+o:  ~o=ooo=o+    :ooooooo+  .====o=o:  .==.  ~~~.~~~~+oooo
    oo==+  ~o+   +:  ~o=ooooo~    .=oooo=o+  .=oo=o=o+  .==   ..~.~..~+oooo
    oo=o:  ~oo+.  .  ~o=oooooo+~~+=ooooo=o+  .ooooo=o~  ~o=   =ooo=oooooooo
    oo=o+  ~o=o=~    ~oooooooooooooooooooo+  .=====+~  .=o=.  +o========ooo
    oo=o:  ~o=ooo:   ~o=oooooo====oooooo=o+          .~ooo=            ~o=o
    oooo+::+o=ooo=+::+ooooo===oooo==oooooo=::::::::++=ooooo::::::::::::+ooo
    ooooooooooooo=ooooooo=oooooo==oooo=ooooooo=ooooo=o=ooooooooooooooo=oooo
    oooo====oooooo===ooooo=+~~.   .~+=oooo============oooooo============ooo
    ooooooooooooooooooo=o:.   ~~~~.   :=ooooooooooooooooooooooooooooooooooo
    ooooooooooooooooooo=~  ~+=oo==o+~  .=oooooooooooooooooooooooooooooooooo
    ooooooooooooooooo=o~  ~o======ooo:  ~=ooooooooooooooooooooooooooooooooo
    ooooooooooooooooo=o~  +o=oooooo===  .=oooooooooo               oooooooo
    ooooooooooooooooo=o~  ~oooo===ooo:  ~ooooooooooo  NODELOGIC 8  oooooooo
    oooooooooooooooooooo~  ~+oooooo+~  .+ooooooooooo               oooooooo
    oooooooooooooooooooo=:.   ~~~~.   ~=ooooooooooooooooooooooooooooooooooo
    oooooooooooooooooooooo=+~..   .~+=ooooooooooooooooooooooooooooooooooooo
    Authorize this $text at https://nodelogic.net/a/$NODEID

EOI
	systemctl restart getty@tty1
}
